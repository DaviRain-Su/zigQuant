# 下一步计划 (Next Steps)

**当前版本**: v0.7.0 ✅
**下一版本**: v0.8.0 📋
**最后更新**: 2025-12-27

---

## 🎯 当前状态

### v0.7.0 已完成 ✅

v0.7.0 "做市策略与回测精度" 已于 2025-12-27 完成，包含：

- ✅ **Clock-Driven 模式** - Tick 驱动策略执行
- ✅ **Pure Market Making 策略** - 双边报价做市
- ✅ **Inventory Management** - 库存风险控制
- ✅ **Data Persistence** - 数据持久化 (DataStore/CandleCache)
- ✅ **Cross-Exchange Arbitrage** - 跨交易所套利
- ✅ **Queue Position Modeling** - 队列位置建模 (借鉴 HFTBacktest)
- ✅ **Dual Latency Simulation** - 双向延迟模拟 (借鉴 HFTBacktest)
- ✅ **25 个示例程序** - 完整覆盖所有功能
- ✅ **624 个单元测试** - 100% 通过

**技术债务**: 无重大技术债务

---

## 🚀 v0.8.0 - 风险管理

**状态**: 📋 规划中
**预计时间**: 3-4 周
**开始时间**: 待定

### 核心目标

1. **RiskEngine 风险引擎**: 仓位限制、杠杆控制、日损失限制
2. **止损/止盈**: 自动平仓逻辑、跟踪止损
3. **资金管理**: Kelly 公式、固定分数、风险平价
4. **风险指标**: VaR、最大回撤监控、夏普比率实时计算
5. **实时监控**: 告警系统、Telegram/Email 通知
6. **Crash Recovery**: 崩溃恢复机制 (借鉴 NautilusTrader)

### Story 列表

| Story ID | 名称 | 优先级 | 预计工时 | 状态 |
|----------|------|--------|----------|------|
| STORY-040 | RiskEngine 风险引擎 | P0 | 4-5 天 | 📋 待开始 |
| STORY-041 | 止损/止盈系统 | P0 | 3-4 天 | 📋 待开始 |
| STORY-042 | 资金管理模块 | P1 | 3-4 天 | 📋 待开始 |
| STORY-043 | 风险指标监控 | P1 | 2-3 天 | 📋 待开始 |
| STORY-044 | 告警和通知系统 | P2 | 2-3 天 | 📋 待开始 |
| STORY-045 | Crash Recovery | P1 | 3-4 天 | 📋 待开始 |

### 依赖关系

```
Story 040 (RiskEngine)
    ↓
Story 041 (止损/止盈) ──→ Story 043 (风险指标)
    ↓                          ↓
Story 042 (资金管理)      Story 044 (告警系统)
                               ↓
                         Story 045 (Crash Recovery)
```

**关键路径**: Story 040 → Story 041 → Story 043 → Story 045

---

## 📋 Story 详情

### Story 040: RiskEngine 风险引擎

**目标**: 实现生产级风险控制引擎

**核心功能**:
```zig
pub const RiskEngine = struct {
    config: RiskConfig,
    positions: *PositionTracker,
    account: *Account,

    /// 订单风控检查
    pub fn checkOrder(self: *Self, order: OrderRequest) !RiskCheckResult {
        // 1. 仓位大小限制
        // 2. 杠杆限制
        // 3. 日损失限制
        // 4. 订单频率限制
    }

    /// Kill Switch - 紧急停止
    pub fn killSwitch(self: *Self) void {
        // 取消所有订单
        // 平掉所有仓位
        // 停止策略
    }
};

pub const RiskConfig = struct {
    max_position_size: Decimal,      // 单个仓位最大值
    max_leverage: Decimal,           // 最大杠杆
    max_daily_loss: Decimal,         // 日损失限制
    max_daily_loss_pct: f64,         // 日损失百分比
    max_orders_per_minute: u32,      // 订单频率限制
    kill_switch_threshold: Decimal,  // Kill Switch 触发阈值
};
```

### Story 041: 止损/止盈系统

**目标**: 实现自动化风险控制

**核心功能**:
```zig
pub const StopLossManager = struct {
    /// 设置止损
    pub fn setStopLoss(self: *Self, position: *Position, price: Decimal) !void;

    /// 设置跟踪止损
    pub fn setTrailingStop(self: *Self, position: *Position, trail_pct: f64) !void;

    /// 设置止盈
    pub fn setTakeProfit(self: *Self, position: *Position, price: Decimal) !void;

    /// 检查并执行
    pub fn checkAndExecute(self: *Self, current_price: Decimal) !void;
};
```

### Story 042: 资金管理模块

**目标**: 实现科学的资金管理策略

**核心功能**:
- **Kelly 公式**: 计算最优仓位
- **固定分数**: 每次交易固定风险比例
- **风险平价**: 基于波动率分配仓位
- **马丁格尔/反马丁格尔**: 可选策略

### Story 043: 风险指标监控

**目标**: 实时计算和监控风险指标

**核心指标**:
- **VaR (Value at Risk)**: 99% 置信区间
- **最大回撤**: 实时计算
- **夏普比率**: 滚动窗口计算
- **盈亏比**: 实时统计
- **胜率**: 实时统计

### Story 044: 告警和通知系统

**目标**: 实现多渠道告警

**支持渠道**:
- **Telegram Bot**: 实时消息推送
- **Email**: 重要告警邮件
- **Webhook**: 自定义集成
- **Console**: 本地日志告警

### Story 045: Crash Recovery

**目标**: 实现崩溃恢复机制 (借鉴 NautilusTrader)

**核心功能**:
```zig
pub const RecoveryManager = struct {
    /// 保存状态到磁盘
    pub fn checkpoint(self: *Self) !void;

    /// 从检查点恢复
    pub fn recover(self: *Self) !void;

    /// 恢复未完成订单
    pub fn recoverOpenOrders(self: *Self) !void;
};
```

---

## 🎯 验收标准

### v0.8.0 验收清单

#### 功能验收
- [ ] RiskEngine 完整实现并通过测试
- [ ] 止损/止盈自动执行
- [ ] 资金管理策略可配置
- [ ] 风险指标实时计算
- [ ] 告警系统多渠道支持
- [ ] Crash Recovery 机制完整

#### 质量验收
- [ ] 700+ 单元测试通过
- [ ] 覆盖率 > 85%
- [ ] 零内存泄漏 (GPA 检测)
- [ ] 风控检查 < 1ms
- [ ] 编译无警告

#### 文档验收
- [ ] 所有 Story 文档完成
- [ ] 风险管理使用指南
- [ ] 配置示例
- [ ] 最佳实践文档

---

## 🔄 后续版本规划

### v0.9.0 - 多交易所支持 (预计 3-4 周)

**主题**: Multi-Exchange & Portfolio Management

**核心目标**:
1. 多交易所并行运行
2. 投资组合管理
3. 交易所间资金调度
4. 统一账户视图

### v1.0.0 - 生产就绪 (预计 4-5 周)

**主题**: Production-Ready Platform

**核心目标**:
1. REST API 服务
2. Web Dashboard
3. Prometheus Metrics
4. 完整运维文档
5. Docker 部署

---

## 📊 成功指标

### 定量指标

| 指标 | v0.7.0 | v0.8.0 目标 | 增长 |
|------|--------|------------|------|
| 单元测试数 | 624 | 700+ | +12% |
| 示例程序 | 25 | 28+ | +12% |
| 文档页数 | ~190 | ~210+ | +10% |
| 模块数量 | 18 | 22+ | +22% |

### 定性指标

- [ ] 风控检查延迟 < 1ms
- [ ] Kill Switch 响应 < 100ms
- [ ] Crash Recovery 时间 < 10s
- [ ] 用户可在 30 分钟内配置完整风控

---

## 💡 建议

### 新贡献者

如果您是新贡献者，建议从以下任务开始：

1. **风险指标实现** (Story 043)
   - VaR 计算
   - 参考现有指标实现
   - 编写单元测试

2. **文档改进**
   - 校对现有文档
   - 添加使用示例

### 有经验的开发者

建议直接承担核心任务：

1. **RiskEngine** (Story 040)
   - 核心风控逻辑
   - 需要深入理解交易系统

2. **Crash Recovery** (Story 045)
   - 复杂的状态管理
   - 需要理解整体架构

---

## 📖 相关文档

### v0.8.0 文档 (待创建)

- [v0.8.0 Overview](./docs/stories/v0.8.0/OVERVIEW.md)
- [Story 040: RiskEngine](./docs/stories/v0.8.0/STORY_040_RISK_ENGINE.md)
- [Story 041: Stop Loss](./docs/stories/v0.8.0/STORY_041_STOP_LOSS.md)
- [Story 042: Money Management](./docs/stories/v0.8.0/STORY_042_MONEY_MANAGEMENT.md)
- [Story 043: Risk Metrics](./docs/stories/v0.8.0/STORY_043_RISK_METRICS.md)
- [Story 044: Alert System](./docs/stories/v0.8.0/STORY_044_ALERT_SYSTEM.md)
- [Story 045: Crash Recovery](./docs/stories/v0.8.0/STORY_045_CRASH_RECOVERY.md)

### 参考文档

- [Roadmap](./roadmap.md)
- [v0.7.0 Overview](./docs/stories/v0.7.0/OVERVIEW.md)
- [竞争分析 - NautilusTrader 风险管理](./docs/architecture/COMPETITIVE_ANALYSIS.md)

---

**创建时间**: 2025-12-27
**最后更新**: 2025-12-27
**维护者**: zigQuant Team
