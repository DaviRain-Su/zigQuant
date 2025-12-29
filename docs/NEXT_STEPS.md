# 下一步行动计划

**更新时间**: 2025-12-29
**当前阶段**: v0.9.0 完成 → v1.0.0 进行中
**架构参考**: [竞争分析](./architecture/COMPETITIVE_ANALYSIS.md) - NautilusTrader/Hummingbot/Freqtrade 深度研究

---

## 📋 架构演进概览

基于对三大顶级量化交易平台的深度分析,zigQuant 的长期架构演进路径:

- **v0.4**: 参数优化 + 策略扩展 ✅ 已完成
- **v0.5**: 事件驱动架构 ✅ 已完成 (MessageBus + Cache + DataEngine + ExecutionEngine)
- **v0.6**: 混合计算模式 ✅ 已完成 (向量化回测 12.6M bars/s + Paper Trading + 热重载)
- **v0.7**: 做市优化 ✅ 已完成 (Clock-Driven + 库存管理 + 数据持久化)
- **v0.8**: 风险管理 ✅ 已完成 (RiskEngine + Stop Loss + Money Management + Alert)
- **v0.9**: Web API ✅ 已完成 (REST API + WebSocket + 统一策略架构)
- **v1.0**: 生产就绪 ← 当前焦点 (Web Dashboard + 架构清理)

详见 [roadmap.md](../roadmap.md) 架构演进战略部分。

---

## ✅ 最新完成工作

### v0.9.0 - Web API & 统一策略架构 (100%) ✅

**完成时间**: 2025-12-29

#### 核心功能

1. **REST API 服务** (Zap/facil.io)
   - ✅ 高性能 HTTP Server
   - ✅ JWT 认证 (内嵌实现)
   - ✅ 策略 API (`/api/v2/strategy`)
   - ✅ 回测 API (`/api/v2/backtest`)
   - ✅ 系统 API (`/api/v2/system`)

2. **WebSocket 实时通信**
   - ✅ 双向通信支持
   - ✅ 频道订阅 (支持通配符)
   - ✅ 实时状态广播
   - ✅ 策略命令 (`strategy.*`)

3. **统一策略架构** (重大重构)
   - ✅ 删除 `grid_runner.zig` - Grid 策略现在通过 StrategyRunner 运行
   - ✅ EngineManager 只使用 `strategy_runners` HashMap
   - ✅ 所有策略类型(含 Grid)统一使用 `/api/v2/strategy` API
   - ✅ StrategyRunner 支持 Grid 特定参数

#### 架构变更

**之前**:
```
EngineManager
├── grid_runners: HashMap     # Grid 专用
├── strategy_runners: HashMap # 其他策略
└── backtest_runners: HashMap
```

**之后**:
```
EngineManager
├── strategy_runners: HashMap  # 所有策略(含 Grid)
└── backtest_runners: HashMap
```

#### 代码统计
| 文件 | 行数 | 描述 |
|------|------|------|
| `src/api/zap_server.zig` | ~900 | REST API 服务 |
| `src/api/websocket.zig` | ~940 | WebSocket 服务 |
| `src/engine/manager.zig` | ~610 | 引擎管理器 |
| `src/engine/runners/strategy_runner.zig` | ~930 | 统一策略运行器 |
| **总计** | **~3380** | **v0.9.0 核心代码** |

#### 测试结果
- ✅ **768/768 单元测试通过**
- ✅ **零内存泄漏**

---

## 🚀 当前进度: 引擎架构统一 (3步计划)

### ✅ Step 1: Grid Runner 移除 (已完成)
- [x] 删除 `grid_runner.zig`
- [x] Grid 策略通过 `StrategyRunner` + `GridStrategy` 运行
- [x] 更新 REST API (`/api/v2/grid` → `/api/v2/strategy`)
- [x] 更新 WebSocket 命令

### ⏳ Step 2: Live Runner 迁移 (待开始)
将 `LiveTradingEngine` 从 `src/trading/live_engine.zig` 迁移到 `src/engine/runners/live_runner.zig`

**任务清单**:
- [ ] 创建 `src/engine/runners/live_runner.zig`
- [ ] 复用 `StrategyRunner` 的模式
- [ ] 整合 `LiveTradingEngine` 的实时交易功能
- [ ] 添加到 `EngineManager`
- [ ] 更新 REST/WebSocket API

### ⏳ Step 3: Paper Trading 清理 (待开始)
合并 `PaperTradingEngine` 到 `StrategyRunner` 的 paper 模式

**任务清单**:
- [ ] 分析 `PaperTradingEngine` 功能
- [ ] 确保 `StrategyRunner.mode = .paper` 完整支持
- [ ] 移除重复代码
- [ ] 更新测试

---

## 📋 后续可执行任务

### 优先级 P0 (必须完成)

#### 1. Web Dashboard (Story 047)
**预计时间**: 5-7 天
**技术栈**: Bun + React + TailwindCSS

**功能清单**:
- [ ] 实时仓位/盈亏展示
- [ ] 策略性能图表
- [ ] 策略启动/停止控制
- [ ] 风险指标面板
- [ ] WebSocket 实时更新

#### 2. 完成引擎架构统一 (Step 2 & 3)
**预计时间**: 2-3 天

**功能清单**:
- [ ] Live Runner 迁移
- [ ] Paper Trading 清理
- [ ] 统一的运行器接口

### 优先级 P1 (高优先级)

#### 3. 多策略组合 (Story 048)
**预计时间**: 3-4 天

**功能清单**:
- [ ] Portfolio 管理器
- [ ] 策略权重分配
- [ ] 风险预算分配
- [ ] 组合绩效分析

#### 4. API 文档 (OpenAPI/Swagger)
**预计时间**: 1-2 天

**功能清单**:
- [ ] OpenAPI 3.0 规范
- [ ] Swagger UI 集成
- [ ] API 使用示例

### 优先级 P2 (中优先级)

#### 5. Binance 适配器 (Story 050)
**预计时间**: 3-4 天

**功能清单**:
- [ ] Binance HTTP API
- [ ] Binance WebSocket
- [ ] 订单管理
- [ ] 账户同步

#### 6. 分布式回测 (Story 049)
**预计时间**: 4-5 天

**功能清单**:
- [ ] 任务分片
- [ ] Worker 节点
- [ ] 结果聚合
- [ ] 进度监控

---

## 📊 当前系统状态

### 已实现功能
- ✅ 完整的交易系统（v0.2.0）
- ✅ 完整的回测系统（v0.3.0）
- ✅ 优化器增强（v0.4.0）
- ✅ 事件驱动架构（v0.5.0）
- ✅ 混合计算模式（v0.6.0）
- ✅ 做市优化（v0.7.0）
- ✅ 风险管理（v0.8.0）
- ✅ Web API + 统一策略架构（v0.9.0）
- ✅ 14 个技术指标
- ✅ 6+ 个内置策略
- ✅ 25 个示例程序
- ✅ 768+ 个单元测试
- ✅ 零内存泄漏
- ✅ ~45,000 行代码

### 核心模块
```
src/
├── core/           核心基础设施 (Decimal, Time, Logger, Config, MessageBus, Cache)
├── exchange/       交易所适配 (Hyperliquid HTTP/WebSocket)
├── market/         市场数据 (OrderBook, Candles, Indicators)
├── trading/        交易引擎 (OrderManager, PositionTracker, LiveEngine)
├── strategy/       策略框架 (IStrategy, 6+ 内置策略含 GridStrategy)
├── backtest/       回测引擎 (向量化回测, 队列建模, 延迟模拟)
├── market_making/  做市模块 (Clock-Driven, 库存管理, 套利)
├── storage/        数据持久化 (DataStore, CandleCache)
├── risk/           风险管理 (RiskEngine, StopLoss, Alert)
├── engine/         引擎管理 (EngineManager, StrategyRunner, BacktestRunner)
├── api/            API 层 (REST Server, WebSocket Server)
├── adapters/       适配器层 (HyperliquidDataProvider/ExecutionClient)
└── cli/            命令行界面 (backtest, optimize, run-strategy)
```

### API 端点一览
```
Authentication:
  POST /api/v2/auth/login     # JWT 登录
  GET  /api/v2/auth/me        # 当前用户
  POST /api/v2/auth/refresh   # 刷新 Token

Strategy (统一 - 支持所有策略类型含 Grid):
  GET  /api/v2/strategy       # 列出所有策略
  POST /api/v2/strategy       # 启动策略
  GET  /api/v2/strategy/:id   # 策略详情
  DELETE /api/v2/strategy/:id # 停止策略
  POST /api/v2/strategy/:id/pause   # 暂停
  POST /api/v2/strategy/:id/resume  # 恢复

Backtest:
  POST /api/v2/backtest/run           # 运行回测
  GET  /api/v2/backtest/:id/progress  # 进度
  GET  /api/v2/backtest/:id/result    # 结果
  POST /api/v2/backtest/:id/cancel    # 取消

System:
  POST /api/v2/system/kill-switch  # 紧急停止
  GET  /api/v2/system/health       # 健康检查
  GET  /api/v2/system/logs         # 日志

WebSocket:
  ws://localhost:8080/ws  # 实时通信
```

### Grid 策略启动示例
```json
POST /api/v2/strategy
{
  "strategy": "grid",
  "symbol": "BTC-USDT",
  "mode": "paper",
  "upper_price": 100000,
  "lower_price": 90000,
  "grid_count": 10,
  "order_size": 0.001,
  "take_profit_pct": 0.5
}
```

---

## 📈 成功指标

### v0.9.0 完成标准 ✅
- [x] REST API 服务 ✅
- [x] WebSocket 实时通信 ✅
- [x] 策略 API ✅
- [x] 统一策略架构 (Grid 整合) ✅
- [x] 768+ 单元测试通过 ✅
- [x] 零内存泄漏 ✅

### v1.0.0 完成标准
- [ ] Web Dashboard
- [ ] 引擎架构统一完成 (Step 2 & 3)
- [ ] API 文档
- [ ] 生产环境部署文档
- [ ] 性能优化

---

## 📅 推荐执行顺序

1. **立即可做**: Web Dashboard (Bun + React) - 用户可视化需求最高
2. **同时可做**: 引擎架构统一 Step 2 & 3 - 代码清理
3. **之后**: 多策略组合 + API 文档
4. **最后**: Binance 适配器 + 分布式回测

---

**更新时间**: 2025-12-29
**当前版本**: v0.9.0 ✅
**下一个版本**: v1.0.0 (生产就绪)
**作者**: Claude
