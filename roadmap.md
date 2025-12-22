# ZigQuant 产品路线图

> 从 0 到生产级量化交易框架的演进路径

**当前版本**: v0.0 (规划阶段)
**目标**: 成为高性能、易用的 Zig 量化交易框架
**最后更新**: 2025-01-22

---

## 🎯 愿景

构建一个结合 **Freqtrade 策略回测能力** 和 **Hummingbot 做市/套利能力** 的高性能量化交易框架，利用 Zig 语言的内存安全和性能优势，打造新一代交易系统。

---

## 📅 版本规划

### v0.1 - Foundation (基础设施) 🏗️
**预计时间**: 2-3 周
**状态**: 📋 待开始

#### 核心目标
搭建项目基础设施，实现核心数据类型和基础工具。

#### Stories
- [x] `stories/v0.1-foundation/001-decimal-type.md` - 高精度 Decimal 类型
- [ ] `stories/v0.1-foundation/002-time-utils.md` - 时间处理工具
- [ ] `stories/v0.1-foundation/003-error-system.md` - 错误处理系统
- [ ] `stories/v0.1-foundation/004-logger.md` - 日志系统
- [ ] `stories/v0.1-foundation/005-config.md` - 配置管理

#### 交付物
- ✅ 项目结构搭建
- ✅ 构建系统配置
- ✅ 核心类型定义
- ✅ 基础工具库

#### 成功指标
- [ ] 所有 Story 测试通过
- [ ] 文档完整性 100%
- [ ] 代码覆盖率 > 90%

---

### v0.2 - MVP (最小可行产品) 🚀
**预计时间**: 3-4 周
**状态**: 📋 待开始
**前置条件**: v0.1 完成

#### 核心目标
**能够连接 Binance，获取行情，执行一次完整的买卖操作。**

#### Stories
- [ ] `stories/v0.2-mvp/001-binance-http.md` - Binance HTTP API
- [ ] `stories/v0.2-mvp/002-orderbook.md` - 订单簿数据结构
- [ ] `stories/v0.2-mvp/003-order-types.md` - 订单类型定义
- [ ] `stories/v0.2-mvp/004-order-manager.md` - 订单管理器
- [ ] `stories/v0.2-mvp/005-balance-tracker.md` - 余额追踪
- [ ] `stories/v0.2-mvp/006-cli-interface.md` - 基础 CLI

#### 功能清单
- [x] 连接 Binance 获取 BTC/USDT 实时价格
- [ ] 显示简单的订单簿
- [ ] 手动下单（市价单/限价单）
- [ ] 查询账户余额
- [ ] 查询订单状态
- [ ] 基础日志输出

#### 演示场景
```bash
$ zigquant
ZigQuant v0.2.0 - MVP
Connected to Binance

> price BTCUSDT
BTC/USDT: $43,250.50

> balance
USDT: 10,000.00 (free)
BTC:  0.00 (free)

> buy 0.01 BTCUSDT market
Order submitted: ORD-123456
Status: FILLED
Price: $43,251.20
Amount: 0.01 BTC
Cost: $432.51 USDT

> balance
USDT: 9,567.49
BTC:  0.01
```

#### 成功指标
- [ ] 能完成一次完整的交易周期
- [ ] 订单状态同步正确
- [ ] 余额计算准确
- [ ] 无内存泄漏

---

### v0.3 - Trading Engine (核心交易引擎) ⚙️
**预计时间**: 4-5 周
**状态**: 📋 待开始
**前置条件**: v0.2 完成

#### 核心目标
实现完整的订单生命周期管理和实时数据流。

#### Stories
- [ ] `stories/v0.3-engine/001-websocket.md` - WebSocket 实时数据
- [ ] `stories/v0.3-engine/002-event-bus.md` - 事件总线
- [ ] `stories/v0.3-engine/003-orderbook-sync.md` - 订单簿同步
- [ ] `stories/v0.3-engine/004-order-lifecycle.md` - 订单生命周期
- [ ] `stories/v0.3-engine/005-position-tracker.md` - 仓位追踪器
- [ ] `stories/v0.3-engine/006-multi-pair.md` - 多交易对支持

#### 功能清单
- [ ] WebSocket 实时行情
- [ ] 本地订单簿维护
- [ ] 订单状态自动同步
- [ ] 仓位实时追踪
- [ ] 事件驱动架构
- [ ] 断线重连机制

#### 成功指标
- [ ] 订单簿更新延迟 < 100ms
- [ ] WebSocket 稳定性 > 99.9%
- [ ] 支持 3+ 交易对同时运行

---

### v0.4 - Strategy Framework (策略框架) 🧠
**预计时间**: 4-5 周
**状态**: 📋 待开始
**前置条件**: v0.3 完成

#### 核心目标
实现策略开发框架和技术指标库。

#### Stories
- [ ] `stories/v0.4-strategy/001-strategy-base.md` - 策略基类
- [ ] `stories/v0.4-strategy/002-indicators.md` - 技术指标库
- [ ] `stories/v0.4-strategy/003-signal-system.md` - 信号系统
- [ ] `stories/v0.4-strategy/004-dual-ma.md` - 双均线策略示例
- [ ] `stories/v0.4-strategy/005-strategy-runner.md` - 策略运行器

#### 指标清单
- [ ] SMA (Simple Moving Average)
- [ ] EMA (Exponential Moving Average)
- [ ] RSI (Relative Strength Index)
- [ ] MACD (Moving Average Convergence Divergence)
- [ ] Bollinger Bands
- [ ] ATR (Average True Range)

#### 演示策略
```zig
// 双均线策略
pub const DualMAStrategy = struct {
    fast_ma: SMA,
    slow_ma: SMA,

    pub fn onKline(self: *DualMAStrategy, kline: Kline) ?Signal {
        const fast = self.fast_ma.update(kline.close);
        const slow = self.slow_ma.update(kline.close);

        if (fast > slow) return Signal{ .direction = .long };
        if (fast < slow) return Signal{ .direction = .short };
        return null;
    }
};
```

#### 成功指标
- [ ] 至少实现 6 个常用指标
- [ ] 策略执行延迟 < 50ms
- [ ] 完整的策略示例

---

### v0.5 - Backtesting (回测系统) 📊
**预计时间**: 4-5 周
**状态**: 📋 待开始
**前置条件**: v0.4 完成

#### 核心目标
实现高性能回测引擎和完整的绩效分析。

#### Stories
- [ ] `stories/v0.5-backtest/001-data-feed.md` - 历史数据管理
- [ ] `stories/v0.5-backtest/002-backtest-engine.md` - 回测引擎
- [ ] `stories/v0.5-backtest/003-metrics.md` - 绩效指标
- [ ] `stories/v0.5-backtest/004-slippage.md` - 滑点模拟
- [ ] `stories/v0.5-backtest/005-report.md` - 报告生成

#### 功能清单
- [ ] 历史数据下载与存储
- [ ] 高性能回测引擎 (> 100K ticks/s)
- [ ] 交易成本模拟（手续费、滑点）
- [ ] 完整的绩效指标
  - Sharpe Ratio
  - Sortino Ratio
  - Maximum Drawdown
  - Win Rate / Profit Factor
- [ ] HTML 报告生成

#### 演示输出
```
Backtest Results:
==================
Period: 2024-01-01 to 2024-12-31
Initial Balance: $10,000
Final Balance: $15,430 (+54.3%)

Performance:
- Total Return: 54.30%
- Sharpe Ratio: 2.15
- Max Drawdown: -12.5%
- Win Rate: 58.3%
- Profit Factor: 1.87

Trades: 142
- Winners: 83 (58.3%)
- Losers: 59 (41.7%)
- Avg Win: $125.50
- Avg Loss: $78.30
```

#### 成功指标
- [ ] 回测速度 > 100,000 ticks/s
- [ ] 与 Freqtrade 结果误差 < 1%
- [ ] 完整的性能报告

---

### v0.6 - Market Making (做市策略) 💹
**预计时间**: 5-6 周
**状态**: 📋 待开始
**前置条件**: v0.5 完成

#### 核心目标
实现纯做市和套利策略。

#### Stories
- [ ] `stories/v0.6-mm/001-pure-mm.md` - 纯做市策略
- [ ] `stories/v0.6-mm/002-inventory.md` - 库存管理
- [ ] `stories/v0.6-mm/003-spread-calc.md` - 价差计算
- [ ] `stories/v0.6-mm/004-cross-arb.md` - 跨交易所套利
- [ ] `stories/v0.6-mm/005-triangle-arb.md` - 三角套利

#### 策略清单
- [ ] Pure Market Making
  - 动态价差调整
  - 库存风险管理
  - Hanging Orders
- [ ] Cross-Exchange Arbitrage
  - 价差监控
  - 同步执行
- [ ] Triangular Arbitrage
  - 三角路径发现
  - 原子化执行

#### 成功指标
- [ ] 做市策略 Sharpe > 2.0
- [ ] 套利捕获率 > 80%
- [ ] 订单执行延迟 < 10ms

---

### v0.7 - Production Ready (生产级功能) 🔧
**预计时间**: 4-5 周
**状态**: 📋 待开始
**前置条件**: v0.6 完成

#### 核心目标
添加生产环境必需的可靠性和监控功能。

#### Stories
- [ ] `stories/v0.7-prod/001-risk-manager.md` - 风险管理系统
- [ ] `stories/v0.7-prod/002-monitoring.md` - 监控与告警
- [ ] `stories/v0.7-prod/003-api-server.md` - REST API
- [ ] `stories/v0.7-prod/004-telegram-bot.md` - Telegram Bot
- [ ] `stories/v0.7-prod/005-crash-recovery.md` - 崩溃恢复

#### 功能清单
- [ ] 风险管理
  - 日损失限制
  - 仓位限制
  - Kill Switch
- [ ] 监控
  - Prometheus metrics
  - Grafana 仪表板
  - 告警通知
- [ ] API 服务
  - RESTful API
  - WebSocket 推送
- [ ] Telegram 集成
  - 交易通知
  - 远程控制
- [ ] 容错机制
  - 状态持久化
  - 自动恢复

#### 成功指标
- [ ] 系统可用性 > 99.5%
- [ ] 故障恢复时间 < 1 分钟
- [ ] 完整的监控覆盖

---

### v0.8 - Advanced Features (高级特性) 🚀
**预计时间**: 持续迭代
**状态**: 📋 待开始
**前置条件**: v0.7 完成

#### 核心目标
实现高级功能和优化。

#### Stories (按优先级)
- [ ] `stories/v0.8-advanced/001-hyperopt.md` - 超参数优化
- [ ] `stories/v0.8-advanced/002-mtf-analysis.md` - 多时间框架分析
- [ ] `stories/v0.8-advanced/003-stop-orders.md` - 止损/止盈系统
- [ ] `stories/v0.8-advanced/004-web-ui.md` - Web 界面
- [ ] `stories/v0.8-advanced/005-dex-connector.md` - DEX 连接器
- [ ] `stories/v0.8-advanced/006-ml-integration.md` - 机器学习集成

#### 功能清单
- [ ] 超参数优化 (TPE/Bayesian)
- [ ] 多时间框架策略
- [ ] 追踪止损
- [ ] Web 管理界面
- [ ] DEX 支持 (Uniswap/PancakeSwap)
- [ ] ONNX 模型推理

---

## 📊 里程碑总览

```
v0.1 Foundation          ████████░░░░░░░░░░░░ (40%)  ← 当前
v0.2 MVP                 ░░░░░░░░░░░░░░░░░░░░ (0%)
v0.3 Trading Engine      ░░░░░░░░░░░░░░░░░░░░ (0%)
v0.4 Strategy Framework  ░░░░░░░░░░░░░░░░░░░░ (0%)
v0.5 Backtesting         ░░░░░░░░░░░░░░░░░░░░ (0%)
v0.6 Market Making       ░░░░░░░░░░░░░░░░░░░░ (0%)
v0.7 Production Ready    ░░░░░░░░░░░░░░░░░░░░ (0%)
v0.8 Advanced Features   ░░░░░░░░░░░░░░░░░░░░ (0%)
```

**整体进度**: 5% (1/20 stories 完成)

---

## 🎯 近期焦点

### 本周目标 (Week 1)
- [ ] 完成 v0.1 所有 Stories
- [ ] 建立测试框架
- [ ] 配置 CI/CD

### 本月目标 (Month 1)
- [ ] v0.1 Foundation 完成
- [ ] v0.2 MVP 开发完成 50%
- [ ] 文档系统完善

### 本季度目标 (Q1 2025)
- [ ] v0.2 MVP 完成
- [ ] v0.3 Trading Engine 完成
- [ ] v0.4 Strategy Framework 启动

---

## 🔄 变更历史

### v0.0 (2025-01-22)
- 🎉 项目启动
- 📝 初始 Roadmap 创建
- 🏗️ 文档结构搭建

---

## 📝 附注

### 开发原则
1. **文档驱动**: Story → Docs → Code
2. **增量交付**: 每个版本都可独立使用
3. **质量优先**: 测试覆盖率 > 速度
4. **用户反馈**: 及时调整优先级

### 版本命名
- `v0.x` - 开发版本
- `v1.0` - 首个稳定版
- `v1.x` - 功能增强
- `v2.0` - 重大架构变更

### 分支策略
- `main` - 稳定版本
- `develop` - 开发主线
- `feature/*` - 功能分支
- `hotfix/*` - 紧急修复

---

*持续更新中...*
