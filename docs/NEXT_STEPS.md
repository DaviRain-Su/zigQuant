# 下一步行动计划

**更新时间**: 2025-12-26
**当前阶段**: 🎉 v0.3.0 完成 (Story 023) → v0.4.0 规划

---

## ✅ 已完成工作

### MVP v0.2.0 - 交易系统核心 (100%) ✅

**完成时间**: 2025-12-25

#### 核心功能
- ✅ Hyperliquid DEX 完整集成
- ✅ HTTP REST API (市场数据、账户、订单查询)
- ✅ WebSocket 实时数据流 (订单簿、订单更新、成交)
- ✅ Orderbook 管理 (快照、增量更新、深度计算)
- ✅ 订单管理 (下单、撤单、批量撤单、查询)
- ✅ 仓位跟踪 (实时 PnL、账户状态同步)
- ✅ CLI 界面 (11 个交易命令 + 交互式 REPL)

#### 技术指标
- ✅ WebSocket 延迟: 0.23ms (< 10ms 目标)
- ✅ 订单执行: ~300ms (< 500ms 目标)
- ✅ 内存占用: ~8MB (< 50MB 目标)
- ✅ 零内存泄漏
- ✅ 173/173 单元测试通过
- ✅ 3/3 集成测试通过

---

### MVP v0.3.0 - 策略回测系统 (100%) ✅

**完成时间**: 2025-12-26 (Story 023)

#### 核心功能
- ✅ **IStrategy 接口重构** (Story 013)
  - 统一的策略接口设计
  - Signal/SignalMetadata 结构
  - StrategyContext 上下文管理

- ✅ **技术指标库** (Stories 014-016)
  - Indicators 基础框架
  - Candles 数据结构
  - 6 个技术指标: SMA, EMA, RSI, MACD, Bollinger Bands, ATR

- ✅ **内置策略** (Stories 017-019)
  - Dual Moving Average Strategy
  - RSI Mean Reversion Strategy
  - Bollinger Breakout Strategy
  - 所有策略经过真实数据验证

- ✅ **回测引擎** (Story 020)
  - BacktestEngine 事件驱动架构
  - HistoricalDataFeed 数据加载
  - OrderExecutor 订单模拟
  - Account/Position 管理

- ✅ **性能分析** (Story 021)
  - PerformanceAnalyzer 完整指标
  - 30+ 性能指标计算
  - 彩色输出格式化

- ✅ **CLI 策略命令** (Story 023) ✨ **LATEST**
  - `zigquant backtest` 完整实现
  - `zigquant optimize` stub
  - `zigquant run-strategy` stub
  - StrategyFactory 策略工厂
  - zig-clap 参数解析
  - 真实 Binance 数据集成（8784 根 K 线）

#### 测试结果
- ✅ **343/343 单元测试通过** (从 173 增长到 343)
- ✅ **零内存泄漏** (GPA 验证)
- ✅ **策略回测验证** (真实 BTC/USDT 2024 年数据):
  - Dual MA: 1 笔交易
  - RSI Mean Reversion: 9 笔交易，**+11.05% 收益** ✨
  - Bollinger Breakout: 2 笔交易

#### 性能指标
- ✅ 策略执行: ~60ms/8k candles (< 1s 目标)
- ✅ 指标计算: < 10ms (< 50ms 目标)
- ✅ 测试覆盖: 343 个测试全部通过

---

## 🚀 当前任务: v0.4.0 规划

### 📋 v0.4.0 目标概览

**主题**: 参数优化和策略扩展
**预计时间**: 2-3 周
**核心目标**: 实现 GridSearchOptimizer + 扩展策略库

---

## 🎯 优先级排序

### P0 - 必须完成 (Story 022)

#### Story 022: GridSearchOptimizer
**预计时间**: 5-7 天
**价值**: 极高 - 自动化策略优化

**功能清单**:
1. **Grid Search 核心**
   - 参数网格定义 (JSON 配置)
   - 参数组合生成器
   - 回测任务调度

2. **并行执行**
   - 线程池实现
   - 任务队列管理
   - 进度跟踪

3. **结果管理**
   - 排序和过滤
   - JSON 结果导出
   - 性能对比报告

4. **Walk-Forward 分析**
   - 训练/测试集分割
   - 滚动窗口验证
   - 过拟合检测

**技术要点**:
- 使用 `std.Thread.Pool` 实现并行
- 参数网格 JSON schema 设计
- 结果缓存和去重
- 内存效率（批处理优化）

**测试要求**:
- 参数组合生成测试
- 并行执行正确性测试
- 性能基准（目标 8 线程 8x 加速）
- 内存泄漏验证

### P1 - 高优先级 (策略扩展)

#### 1. 更多技术指标 (3-4 天)
**目标**: 扩展到 15+ 指标

**新增指标**:
- [ ] Stochastic RSI
- [ ] Williams %R
- [ ] CCI (Commodity Channel Index)
- [ ] ADX (Average Directional Index)
- [ ] Ichimoku Cloud
- [ ] VWAP (Volume Weighted Average Price)
- [ ] OBV (On Balance Volume)
- [ ] Fibonacci Retracement
- [ ] Pivot Points

**实现要点**:
- 遵循现有 Indicator 接口
- 添加单元测试
- 文档和使用示例

#### 2. 更多内置策略 (4-5 天)
**目标**: 5+ 经典策略

**新增策略**:
- [ ] Triple MA Crossover
- [ ] MACD Histogram Strategy
- [ ] Trend Following (ADX + EMA)
- [ ] Mean Reversion (Stochastic RSI)
- [ ] Breakout with Volume Confirmation

**实现要点**:
- JSON 配置文件
- 参数默认值和范围
- 回测验证
- 策略文档

### P2 - 中优先级 (用户体验)

#### 1. Backtest 结果导出 (2-3 天)
**目标**: 实现 --output 参数

**功能**:
- [ ] JSON 结果保存
- [ ] 交易明细导出
- [ ] Equity curve 数据
- [ ] 指标值导出

**格式示例**:
```json
{
  "strategy": "dual_ma",
  "config": {...},
  "results": {
    "trades": [...],
    "metrics": {...},
    "equity_curve": [...]
  }
}
```

#### 2. 策略开发指南 (2 天)
**目标**: 用户文档

**内容**:
- [ ] 如何创建自定义策略
- [ ] 如何添加自定义指标
- [ ] 配置文件格式说明
- [ ] 最佳实践和示例
- [ ] 调试技巧

#### 3. 回测性能优化 (1-2 天)
**目标**: < 30ms/8k candles

**优化方向**:
- [ ] 指标计算向量化
- [ ] 内存预分配优化
- [ ] 减少不必要的分配
- [ ] 缓存常用计算结果

### P3 - 低优先级 (未来增强)

#### 1. WebSocket 实时交易 (1-2 周)
- [ ] 实时数据流集成
- [ ] 异步订单执行
- [ ] run-strategy --paper 实现
- [ ] run-strategy --live 实现

#### 2. 风险管理增强 (1 周)
- [ ] 仓位大小计算
- [ ] 动态止损止盈
- [ ] 最大回撤控制
- [ ] Kelly 公式资金管理

#### 3. 监控和报告 (1 周)
- [ ] 实时性能监控
- [ ] HTML/PDF 报告生成
- [ ] 策略对比仪表盘
- [ ] 邮件/Webhook 通知

---

## 📅 开发时间线（v0.4.0）

| 任务 | 优先级 | 预计时间 | 状态 |
|------|--------|---------|------|
| **Story 022: GridSearchOptimizer** | P0 | 5-7 天 | 🔜 下一步 |
| 更多技术指标 (15+) | P1 | 3-4 天 | ⏳ 待开始 |
| 更多内置策略 (5+) | P1 | 4-5 天 | ⏳ 待开始 |
| Backtest 结果导出 | P2 | 2-3 天 | ⏳ 待开始 |
| 策略开发指南 | P2 | 2 天 | ⏳ 待开始 |
| 回测性能优化 | P2 | 1-2 天 | ⏳ 待开始 |

**v0.4.0 总预计时间**: 2-3 周

---

## 🎯 今天就开始！Story 022 实现计划

### Step 1: 设计参数网格格式 (0.5 天)

**参数网格 JSON Schema**:
```json
{
  "strategy": "dual_ma",
  "base_config": "examples/strategies/dual_ma.json",
  "param_grid": {
    "fast_period": [5, 10, 15, 20],
    "slow_period": [20, 30, 40, 50],
    "ma_type": ["sma", "ema"]
  },
  "data_file": "data/BTCUSDT_1h_2024.csv",
  "objective": "sharpe_ratio",  // or "total_return", "profit_factor", etc.
  "walk_forward": {
    "enabled": true,
    "train_size": 0.7,
    "test_size": 0.3
  }
}
```

### Step 2: 实现核心组件 (2-3 天)

**文件结构**:
```
src/backtest/optimizer.zig          # GridSearchOptimizer 核心
src/backtest/param_grid.zig         # 参数网格生成
src/backtest/optimization_result.zig # 优化结果类型
```

**核心接口**:
```zig
pub const GridSearchOptimizer = struct {
    allocator: Allocator,
    logger: Logger,
    thread_pool: *std.Thread.Pool,

    pub fn init(allocator: Allocator, logger: Logger, thread_count: usize) !GridSearchOptimizer;
    pub fn deinit(self: *GridSearchOptimizer) void;

    pub fn optimize(
        self: *GridSearchOptimizer,
        strategy_name: []const u8,
        grid_config_path: []const u8,
    ) !OptimizationResult;
};

pub const OptimizationResult = struct {
    total_combinations: usize,
    completed: usize,
    best_params: std.json.Value,
    best_score: Decimal,
    all_results: []ParamResult,

    pub fn deinit(self: *OptimizationResult) void;
    pub fn saveToJSON(self: *OptimizationResult, file_path: []const u8) !void;
};
```

### Step 3: 实现并行执行 (1-2 天)

**线程池使用**:
```zig
// 创建任务
var tasks = std.ArrayList(BacktestTask).init(allocator);
for (param_combinations) |params| {
    try tasks.append(.{
        .params = params,
        .strategy_name = strategy_name,
        .data_file = data_file,
    });
}

// 并行执行
var results = try self.thread_pool.execute(tasks.items);

// 汇总结果
for (results) |result| {
    try all_results.append(result);
}
```

### Step 4: 实现 CLI 命令 (1 天)

**更新 optimize.zig**:
```bash
zigquant optimize \
  --strategy dual_ma \
  --param-grid grid.json \
  --output results.json \
  --threads 8
```

### Step 5: 测试和文档 (1 天)

- [ ] 单元测试（参数生成、并行执行）
- [ ] 集成测试（完整优化流程）
- [ ] 性能测试（8 线程加速比）
- [ ] 文档（API + 使用指南）

---

## 📚 文档更新清单

### v0.3.0 完成文档 ✅
- ✅ `docs/MVP_V0.3.0_PROGRESS.md` - v0.3.0 进度总结
- ✅ `docs/features/backtest/changelog.md` - 更新 v0.3.0 发布内容
- [ ] `docs/NEXT_STEPS.md` - 更新下一步计划（本文档）
- [ ] `docs/features/backtest/README.md` - 添加 CLI 使用说明
- [ ] `README.md` - 添加 backtest 命令示例

### v0.4.0 待创建文档
- [ ] `docs/features/optimizer/` - GridSearchOptimizer 完整文档
- [ ] `docs/guides/STRATEGY_DEVELOPMENT.md` - 策略开发指南
- [ ] `docs/guides/BACKTEST_GUIDE.md` - 回测用户指南
- [ ] `docs/guides/OPTIMIZATION_GUIDE.md` - 参数优化指南

---

## 🔮 长期愿景（v0.5.0+）

### Phase 3: 实盘交易系统 (v0.5.0)
- 实时策略执行
- Paper trading 模式
- 风险管理集成
- 监控和告警

### Phase 4: 生产化 (v0.6.0)
- 持久化存储
- 分布式回测
- Web 管理界面
- API 服务

### Phase 5: 高级分析 (v1.0.0)
- 组合优化
- Monte Carlo 模拟
- 机器学习集成
- 多策略组合

---

## 🎯 推荐行动

### 本周计划（建议）

**Day 1-2**: Story 022 设计和核心实现
- 设计参数网格 JSON schema
- 实现 ParamGrid 生成器
- 实现 GridSearchOptimizer 核心逻辑

**Day 3-4**: 并行执行和结果管理
- 集成 Thread.Pool
- 实现结果排序和导出
- 性能优化

**Day 5**: CLI 集成和测试
- 更新 optimize 命令
- 单元测试和集成测试
- 文档编写

**Day 6-7**: 策略扩展（如果时间允许）
- 添加 2-3 个新指标
- 添加 1-2 个新策略
- 回测验证

---

## 📊 当前系统状态

### 已实现功能
- ✅ 完整的交易系统（v0.2.0）
- ✅ 完整的回测系统（v0.3.0）
- ✅ 6 个技术指标
- ✅ 3 个内置策略
- ✅ CLI backtest 命令
- ✅ 343 个单元测试
- ✅ 零内存泄漏

### 待实现功能
- ⏳ 参数优化（Story 022）
- ⏳ 更多指标和策略
- ⏳ 实盘交易集成
- ⏳ 风险管理
- ⏳ Web 界面

---

## 🚀 快速开始 Story 022

```bash
cd /home/davirain/dev/zigQuant

# Step 1: 创建 optimizer 模块
mkdir -p src/backtest
touch src/backtest/optimizer.zig
touch src/backtest/param_grid.zig

# Step 2: 设计参数网格格式
touch examples/param_grids/dual_ma_grid.json

# Step 3: 开始实现
vim src/backtest/optimizer.zig

# Step 4: 运行测试（开发过程中）
zig build test

# Step 5: 文档
mkdir -p docs/features/optimizer
touch docs/features/optimizer/README.md
```

---

## 📈 成功指标

### v0.4.0 完成标准
- [ ] GridSearchOptimizer 实现并通过所有测试
- [ ] 至少 10 个技术指标
- [ ] 至少 5 个内置策略
- [ ] `zigquant optimize` 命令完整实现
- [ ] 完整文档（API + 用户指南）
- [ ] 性能达标（8 线程 5x+ 加速）
- [ ] 零内存泄漏
- [ ] 400+ 单元测试通过

---

**更新时间**: 2025-12-26
**当前版本**: v0.3.0 ✅
**下一个版本**: v0.4.0 (Story 022 + 策略扩展)
**作者**: Claude (Sonnet 4.5)
