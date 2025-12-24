# zigQuant 项目状态与后续开发路线图

**更新时间**: 2025-12-25
**项目版本**: v0.2.0-dev (MVP 阶段)

---

## 📊 当前项目状态总览

### 整体进度

| 层次 | 模块数 | 完成度 | 状态 |
|------|--------|--------|------|
| **Core 层** | 5/5 | 100% | ✅ 已完成 |
| **Exchange 层** | 2/2 | 95% | ✅ 基本完成 |
| **Trading 层** | 5/5 | 85% | 🚧 部分完成 |
| **CLI 层** | 1/1 | 100% | ✅ 已完成 |
| **Strategy 层** | 0/? | 0% | 📋 未开始 |
| **Backtest 层** | 0/? | 0% | 📋 未开始 |
| **Risk 层** | 0/? | 0% | 📋 未开始 |

**MVP 整体完成度**: **约 70%**

---

## ✅ 已完成的工作

### 1. Core 层 (100% ✅)

**源文件** (5个):
- `src/core/time.zig` - 时间处理和时区转换
- `src/core/decimal.zig` - 高精度十进制运算
- `src/core/errors.zig` - 统一错误处理系统
- `src/core/logger.zig` - 双模式日志系统 (printf-style + structured)
- `src/core/config.zig` - JSON配置加载

**文档** (6个文件 × 5个模块 = 30个文件):
- ✅ time/ - README, api, implementation, testing, bugs, changelog
- ✅ decimal/ - README, api, implementation, testing, bugs, changelog
- ✅ error-system/ - README, api, implementation, testing, bugs, changelog
- ✅ logger/ - README, api, implementation, testing, bugs, changelog, usage-guide
- ✅ config/ - README, api, implementation, testing, bugs, changelog

**关键功能**:
- ✅ Timestamp 和 Timeframe 类型
- ✅ Decimal 类型 (i128 + u8 scale, 18位精度)
- ✅ 统一错误码系统
- ✅ 彩色日志输出
- ✅ 双模式日志 (自动类型检测)
- ✅ JSON配置加载

---

### 2. Exchange 层 (95% ✅)

**源文件** (15个):
- `src/exchange/interface.zig` - IExchange vtable 接口
- `src/exchange/types.zig` - 统一交易所数据类型
- `src/exchange/registry.zig` - 交易所注册表
- `src/exchange/symbol_mapper.zig` - 符号映射器
- `src/exchange/hyperliquid/connector.zig` - Hyperliquid连接器
- `src/exchange/hyperliquid/http.zig` - HTTP客户端
- `src/exchange/hyperliquid/websocket.zig` - WebSocket客户端
- `src/exchange/hyperliquid/auth.zig` - Ed25519签名
- `src/exchange/hyperliquid/info_api.zig` - Info API端点
- `src/exchange/hyperliquid/exchange_api.zig` - Exchange API端点
- `src/exchange/hyperliquid/types.zig` - Hyperliquid特定类型
- `src/exchange/hyperliquid/ws_types.zig` - WebSocket消息类型
- `src/exchange/hyperliquid/message_handler.zig` - 消息处理器
- `src/exchange/hyperliquid/subscription.zig` - 订阅管理
- `src/exchange/hyperliquid/rate_limiter.zig` - 速率限制器

**文档** (完整):
- ✅ exchange-router/ - README, api, implementation, testing, bugs, changelog
- ✅ hyperliquid-connector/ - README, api, implementation, testing, bugs, changelog

**关键功能**:
- ✅ IExchange 抽象接口 (VTable模式)
- ✅ ExchangeRegistry (MVP: 单交易所)
- ✅ SymbolMapper (符号转换)
- ✅ Hyperliquid HTTP/WebSocket完整实现
- ✅ Ed25519签名认证
- ✅ Signer懒加载机制
- ✅ 自动重连机制
- ✅ 速率限制 (20 req/s)
- ✅ getOpenOrders 接口

**剩余工作** (5%):
- ⏳ 完善WebSocket订阅管理
- ⏳ 增加更多错误恢复机制

---

### 3. Trading 层 (85% 🚧)

**源文件** (5个):
- `src/trading/order_manager.zig` - 订单管理器
- `src/trading/order_store.zig` - 订单存储
- `src/trading/position_tracker.zig` - 仓位跟踪器
- `src/trading/position.zig` - 仓位数据结构
- `src/trading/account.zig` - 账户信息

**文档** (完整):
- ✅ order-manager/ - README, api, implementation, testing, bugs, changelog
- ✅ position-tracker/ - README, api, implementation, testing, bugs, changelog
- ✅ order-system/ - README, api, implementation, testing, bugs, changelog
- ✅ orderbook/ - README, api, implementation, testing, bugs, changelog

**关键功能**:
- ✅ OrderManager (订单提交、取消、查询)
- ✅ OrderStore (双索引: client_id + exchange_id)
- ✅ PositionTracker (仓位跟踪和PnL计算)
- ✅ Position (szi, entry_price, unrealized_pnl)
- ✅ Account (余额、保证金)
- ✅ 订单状态机 (pending → open → filled/canceled)
- ✅ 回调系统 (on_order_update, on_order_fill)

**剩余工作** (15%):
- ⏳ 实际orderbook数据结构和算法
- ⏳ WebSocket事件集成测试
- ⏳ 止损/止盈订单
- ⏳ Portfolio-level PnL汇总

---

### 4. CLI 层 (100% ✅)

**源文件** (3个):
- `src/cli/cli.zig` - CLI结构和命令路由
- `src/cli/repl.zig` - REPL交互循环
- `src/cli/format.zig` - 格式化输出

**主入口**:
- `src/main.zig` - CLI程序入口

**文档** (完整):
- ✅ cli/ - README, api, implementation, testing, bugs, changelog

**关键功能**:
- ✅ 11个命令: help, price, book, balance, positions, orders, buy, sell, cancel, cancel-all, repl
- ✅ 彩色控制台输出 (ANSI codes)
- ✅ REPL交互模式
- ✅ 配置文件加载
- ✅ 所有命令在 Hyperliquid testnet 测试通过

**已修复Bug** (6个):
- ✅ Bug #1: 控制台输出缓冲未刷新
- ✅ Bug #2: console_writer 悬空指针
- ✅ Bug #3: 内存泄漏
- ✅ Bug #4: Signer 懒加载
- ✅ Bug #5: orders 命令未实现
- ✅ Bug #6: 日志格式问题

**测试结果**:
- ✅ 11/11 命令测试通过
- ✅ 0 内存泄漏
- ✅ 启动时间 < 200ms
- ✅ 内存占用 < 10MB

---

## 📋 未开始的模块

### 1. Strategy 层 (0% 📋)

**计划模块**:
- `src/strategy/interface.zig` - 策略接口
- `src/strategy/context.zig` - 策略上下文
- `src/strategy/signal.zig` - 信号系统
- `src/strategy/indicators/` - 技术指标库
  - SMA, EMA, RSI, MACD, Bollinger Bands, ATR, etc.
- `src/strategy/builtin/` - 内置策略
  - Dual MA, RSI Divergence, Pure Market Making, etc.

**优先级**: ⭐⭐⭐ 高 (MVP核心功能)

---

### 2. Backtest 层 (0% 📋)

**计划模块**:
- `src/backtest/engine.zig` - 回测引擎
- `src/backtest/data_feed.zig` - 历史数据源
- `src/backtest/simulator.zig` - 成交模拟
- `src/backtest/metrics.zig` - 性能指标
- `src/backtest/report.zig` - 报告生成

**优先级**: ⭐⭐ 中 (验证策略必需)

---

### 3. Risk 层 (0% 📋)

**计划模块**:
- `src/risk/manager.zig` - 风险管理器
- `src/risk/limits.zig` - 风险限制
- `src/risk/protections.zig` - 保护机制
- `src/risk/kill_switch.zig` - 紧急停止

**优先级**: ⭐⭐⭐ 高 (生产环境必需)

---

### 4. Market Data 层 (部分完成)

**计划模块**:
- `src/market/orderbook.zig` - 订单簿管理 (⏳ 文档已完成,代码待实现)
- `src/market/ticker.zig` - Ticker数据
- `src/market/kline.zig` - K线数据
- `src/market/trade.zig` - 成交记录
- `src/market/aggregator.zig` - 跨交易所聚合

**优先级**: ⭐⭐ 中

---

## 🚀 后续开发路线图

### Phase 1: 完善 MVP 核心 (1-2周)

**目标**: 完成 v0.2.0 MVP 发布

#### 1.1 完成 Trading 层剩余工作 (3-4天)

- [ ] 实现 orderbook 数据结构
  - [ ] Level (price, quantity, num_orders)
  - [ ] OrderBook (bids, asks)
  - [ ] OrderBookManager (snapshot, update)
  - [ ] 测试: applySnapshot, applyUpdate, getSlippage
- [ ] WebSocket 事件集成测试
  - [ ] 订单更新事件
  - [ ] 仓位更新事件
  - [ ] 账户余额更新事件
- [ ] Portfolio-level PnL 汇总
  - [ ] 跨币种PnL计算
  - [ ] 总账户价值

**验收标准**:
- ✅ Orderbook 正确处理 snapshot 和 delta 更新
- ✅ WebSocket 事件正确触发回调
- ✅ PnL 计算准确

#### 1.2 增加集成测试 (2-3天)

- [ ] 完整交易流程测试
  - [ ] 连接交易所 → 查询市场 → 下单 → 监听成交 → 更新仓位
- [ ] 错误场景测试
  - [ ] 网络断开重连
  - [ ] API错误处理
  - [ ] 订单拒绝处理
- [ ] 性能测试
  - [ ] WebSocket消息处理延迟
  - [ ] 订单簿更新性能
  - [ ] 内存占用

**验收标准**:
- ✅ 所有集成测试通过
- ✅ 性能达标 (延迟 < 10ms, 内存 < 50MB)

#### 1.3 MVP v0.2.0 发布 (1天)

- [ ] 创建 CHANGELOG.md (v0.2.0)
- [ ] 创建 README.md (项目概述)
- [ ] 打 git tag: v0.2.0
- [ ] 生成发布文档

**MVP v0.2.0 功能清单**:
- ✅ Hyperliquid DEX 完整集成
- ✅ 实时市场数据 (HTTP + WebSocket)
- ✅ 订单管理 (下单、撤单、查询)
- ✅ 仓位跟踪和 PnL 计算
- ✅ CLI 界面 (11个命令 + REPL)
- ✅ 配置文件系统
- ✅ 日志系统
- ✅ 完整文档

---

### Phase 2: 策略框架 (2-3周)

#### 2.1 策略接口设计 (3天)

**文件**:
- `src/strategy/interface.zig` - IStrategy 接口

**接口定义**:
```zig
pub const IStrategy = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        // 生命周期
        onInit: *const fn (*anyopaque, *StrategyContext) anyerror!void,
        onStart: *const fn (*anyopaque) anyerror!void,
        onStop: *const fn (*anyopaque) void,
        onDestroy: *const fn (*anyopaque) void,

        // 市场数据事件
        onTick: *const fn (*anyopaque, Ticker) anyerror!void,
        onOrderbook: *const fn (*anyopaque, Orderbook) anyerror!void,
        onTrade: *const fn (*anyopaque, Trade) anyerror!void,
        onKline: *const fn (*anyopaque, Kline) anyerror!void,

        // 订单事件
        onOrderUpdate: *const fn (*anyopaque, Order) anyerror!void,
        onOrderFill: *const fn (*anyopaque, Fill) anyerror!void,

        // 仓位事件
        onPositionUpdate: *const fn (*anyopaque, Position) anyerror!void,
    };
};

pub const StrategyContext = struct {
    allocator: std.mem.Allocator,
    exchange: *ExchangeRegistry,
    order_mgr: *OrderManager,
    position_tracker: *PositionTracker,
    logger: Logger,

    // 策略API
    pub fn submitOrder(self: *StrategyContext, req: OrderRequest) !Order;
    pub fn cancelOrder(self: *StrategyContext, order_id: u64) !void;
    pub fn getPosition(self: *StrategyContext, pair: TradingPair) ?Position;
    pub fn getBalance(self: *StrategyContext) !Balance;
};
```

**任务**:
- [ ] 实现 IStrategy 接口
- [ ] 实现 StrategyContext
- [ ] 实现 StrategyRegistry (策略注册表)
- [ ] 编写文档

#### 2.2 技术指标库 (5-7天)

**文件结构**:
```
src/strategy/indicators/
├── interface.zig       # 指标接口
├── sma.zig            # 简单移动平均
├── ema.zig            # 指数移动平均
├── rsi.zig            # 相对强弱指数
├── macd.zig           # MACD
├── bollinger.zig      # 布林带
├── atr.zig            # 平均真实波幅
└── volume.zig         # 成交量指标
```

**优先级**:
1. ⭐⭐⭐ SMA, EMA (移动平均)
2. ⭐⭐⭐ RSI (超买超卖)
3. ⭐⭐ MACD (趋势)
4. ⭐⭐ Bollinger Bands (波动性)
5. ⭐ ATR (风险管理)

**任务**:
- [ ] 实现 IIndicator 接口
- [ ] 实现 SMA 和 EMA
- [ ] 实现 RSI
- [ ] 实现 MACD
- [ ] 实现 Bollinger Bands
- [ ] 单元测试 (验证算法正确性)
- [ ] 性能测试 (1M数据点更新 < 100ms)

#### 2.3 第一个策略: Dual MA (3天)

**文件**: `src/strategy/builtin/dual_ma.zig`

**策略逻辑**:
- 短期 MA (例如 7) 和 长期 MA (例如 25)
- 金叉: 短期上穿长期 → 买入
- 死叉: 短期下穿长期 → 卖出

**任务**:
- [ ] 实现 Dual MA 策略
- [ ] 参数配置 (fast_period, slow_period, amount)
- [ ] 回测测试
- [ ] 文档

#### 2.4 策略引擎 (2天)

**文件**: `src/strategy/engine.zig`

**功能**:
- 策略加载和卸载
- 策略调度 (多策略并行)
- 事件分发 (market data → strategies)
- 策略生命周期管理

**任务**:
- [ ] 实现 StrategyEngine
- [ ] 实现事件总线
- [ ] 实现策略调度器
- [ ] 测试

---

### Phase 3: 回测系统 (2-3周)

#### 3.1 历史数据存储 (3天)

**文件**:
- `src/storage/sqlite.zig` - SQLite存储
- `src/storage/csv.zig` - CSV导入导出
- `src/storage/timeseries.zig` - 时间序列数据

**Schema**:
```sql
CREATE TABLE klines (
    id INTEGER PRIMARY KEY,
    pair TEXT NOT NULL,
    timeframe TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    open TEXT NOT NULL,
    high TEXT NOT NULL,
    low TEXT NOT NULL,
    close TEXT NOT NULL,
    volume TEXT NOT NULL,
    UNIQUE(pair, timeframe, timestamp)
);

CREATE TABLE trades (
    id INTEGER PRIMARY KEY,
    pair TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    price TEXT NOT NULL,
    quantity TEXT NOT NULL,
    side TEXT NOT NULL
);
```

**任务**:
- [ ] SQLite数据库设计
- [ ] 数据导入 (从CSV)
- [ ] 数据查询 (时间范围)
- [ ] 测试

#### 3.2 回测引擎 (5天)

**文件**: `src/backtest/engine.zig`

**核心功能**:
- 时间模拟循环
- 订单簿模拟
- 成交模拟 (slippage model)
- 费用计算
- PnL计算

**流程**:
```
for each timestamp in historical_data:
    1. Load market state (orderbook, price)
    2. Process pending orders (check fills, stop triggers)
    3. Call strategy.onTick()
    4. Update portfolio state
    5. Record metrics
```

**任务**:
- [ ] 实现 BacktestEngine
- [ ] 实现 OrderSimulator (成交模拟)
- [ ] 实现 SlippageModel
- [ ] 实现 FeeCalculator
- [ ] 测试 (验证与实盘一致性)

#### 3.3 性能指标和报告 (3天)

**文件**:
- `src/backtest/metrics.zig` - 性能指标
- `src/backtest/report.zig` - 报告生成

**指标**:
- 总回报 (Total Return)
- 夏普比率 (Sharpe Ratio)
- 索提诺比率 (Sortino Ratio)
- 最大回撤 (Max Drawdown)
- 胜率 (Win Rate)
- 盈亏比 (Profit Factor)
- 交易统计 (Trade Statistics)

**报告格式**:
- 文本报告 (Markdown)
- JSON报告
- 权益曲线 (CSV)

**任务**:
- [ ] 实现指标计算
- [ ] 实现报告生成
- [ ] CLI集成 (`zigQuant backtest -s dual_ma -d 2024-01-01 -e 2024-12-31`)

---

### Phase 4: 风险管理 (1-2周)

#### 4.1 风险管理器 (3天)

**文件**: `src/risk/manager.zig`

**功能**:
- 订单前检查 (pre-trade checks)
- 仓位限制 (max position size)
- 杠杆限制 (max leverage)
- 日损失限制 (daily loss limit)
- 总风险敞口 (portfolio risk exposure)

**任务**:
- [ ] 实现 RiskManager
- [ ] 实现 RiskLimits 配置
- [ ] 集成到 OrderManager
- [ ] 测试

#### 4.2 保护机制 (2天)

**文件**: `src/risk/protections.zig`

**功能**:
- 快速亏损保护 (rapid loss protection)
- 连续亏损保护 (consecutive loss protection)
- 波动性保护 (volatility protection)

**任务**:
- [ ] 实现保护机制
- [ ] 配置化
- [ ] 测试

#### 4.3 Kill Switch (1天)

**文件**: `src/risk/kill_switch.zig`

**功能**:
- 紧急停止所有策略
- 撤销所有挂单
- 平掉所有仓位 (可选)

**任务**:
- [ ] 实现 KillSwitch
- [ ] CLI集成 (`zigQuant kill-switch`)
- [ ] 测试

---

### Phase 5: 生产环境准备 (1-2周)

#### 5.1 监控和告警 (3天)

**文件**:
- `src/monitoring/metrics.zig` - 指标收集
- `src/monitoring/alerter.zig` - 告警系统
- `src/monitoring/health.zig` - 健康检查

**功能**:
- 系统指标 (CPU, 内存, 延迟)
- 交易指标 (订单数, 成交量, PnL)
- 告警 (Telegram, Email)

**任务**:
- [ ] 实现指标收集
- [ ] 实现告警系统
- [ ] Telegram集成
- [ ] 健康检查端点

#### 5.2 配置管理 (2天)

**功能**:
- 多环境配置 (dev, testnet, prod)
- 热重载 (配置文件变更自动重载)
- 密钥管理 (加密存储)

**任务**:
- [ ] 多环境配置支持
- [ ] 配置热重载
- [ ] 密钥加密存储

#### 5.3 日志和审计 (2天)

**功能**:
- 结构化日志
- 日志轮转
- 审计日志 (所有订单操作)

**任务**:
- [ ] 日志轮转
- [ ] 审计日志系统
- [ ] 日志查询工具

---

## 📅 时间线总结

| Phase | 内容 | 时间 | 状态 |
|-------|-----|------|------|
| **Phase 1** | 完善 MVP 核心 | 1-2周 | 📋 待开始 |
| **Phase 2** | 策略框架 | 2-3周 | 📋 待开始 |
| **Phase 3** | 回测系统 | 2-3周 | 📋 待开始 |
| **Phase 4** | 风险管理 | 1-2周 | 📋 待开始 |
| **Phase 5** | 生产环境准备 | 1-2周 | 📋 待开始 |
| **总计** | **MVP v0.2.0 → v0.3.0** | **7-12周** | |

---

## 🎯 下一步行动建议

### 立即行动 (本周)

1. **完成 Orderbook 实现** (2天)
   - 实现 `src/market/orderbook.zig`
   - 测试 snapshot 和 delta 更新
   - 性能测试

2. **WebSocket 集成测试** (1天)
   - 订单更新事件测试
   - 仓位更新事件测试
   - 端到端流程测试

3. **MVP v0.2.0 发布** (1天)
   - 创建 CHANGELOG
   - 创建 README
   - 打 git tag
   - 发布文档

### 近期目标 (2周内)

4. **开始 Strategy 框架** (1周)
   - 设计 IStrategy 接口
   - 实现 StrategyContext
   - 实现第一个指标 (SMA/EMA)

5. **实现 Dual MA 策略** (3天)
   - 策略实现
   - 参数配置
   - 测试

### 中期目标 (1-2月内)

6. **完成回测系统**
   - 历史数据存储
   - 回测引擎
   - 性能报告

7. **风险管理系统**
   - 风险限制
   - 保护机制
   - Kill Switch

---

## 📝 开发工作流建议

### 1. 分支管理

```bash
main (稳定版本)
  └── develop (开发主分支)
       ├── feature/orderbook (Orderbook实现)
       ├── feature/strategy-framework (策略框架)
       └── feature/backtest (回测系统)
```

### 2. 提交规范

```
feat: 新功能
fix: Bug修复
docs: 文档更新
refactor: 重构
test: 测试
perf: 性能优化
```

### 3. 开发流程

```
1. 创建 feature 分支
2. 实现功能 + 单元测试
3. 更新文档
4. 提交 PR 到 develop
5. Code review
6. 合并到 develop
7. 定期合并到 main (发布版本)
```

### 4. 测试策略

- **单元测试**: 每个模块都有测试
- **集成测试**: 测试模块间交互
- **性能测试**: 关键路径性能
- **回归测试**: 每次发布前运行全部测试

---

## 🔧 开发环境

### 必需工具

- Zig 0.15.2+
- Git
- SQLite3 (回测数据存储)
- jq (JSON处理)

### 推荐工具

- VSCode + Zig 插件
- ZLS (Zig Language Server)
- kcov (代码覆盖率)
- hyperfine (性能测试)

### 测试环境

- Hyperliquid testnet (https://app.hyperliquid-testnet.xyz)
- 测试账户需要 testnet 资金

---

## 📚 相关文档

- [ARCHITECTURE.md](./ARCHITECTURE.md) - 系统架构设计
- [docs/features/](./features/) - 各模块详细文档
- [TASK_PLAN_2025-12-25.md](./TASK_PLAN_2025-12-25.md) - 近期任务计划
- [SUMMARY_2025-12-24.md](./SUMMARY_2025-12-24.md) - 最近工作总结

---

## ❓ 常见问题

### Q1: 为什么先实现 Hyperliquid 而不是 Binance?

A: 见 [ADR-002](./decisions/002-hyperliquid-first-exchange.md)。主要原因:
- Hyperliquid 是 DEX,无KYC限制
- API简单清晰
- 支持 testnet
- 适合快速原型验证

### Q2: 什么时候支持其他交易所?

A: Phase 6 (MVP完成后)。架构已支持多交易所,只需实现 IExchange 接口。

### Q3: 回测系统支持哪些数据源?

A:
- 本地 SQLite 数据库
- CSV 文件导入
- (未来) 直接从交易所下载历史数据

### Q4: 策略如何热更新?

A: (未来功能) 策略引擎支持动态加载/卸载策略,无需重启程序。

---

## 📞 联系方式

有问题或建议?
- 创建 GitHub Issue
- 查看文档: `docs/`
- 阅读代码: `src/`

---

*文档更新时间: 2025-12-25*
*项目版本: v0.2.0-dev*
*作者: Claude (Sonnet 4.5)*
