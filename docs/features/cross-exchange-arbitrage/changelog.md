# Cross-Exchange Arbitrage 变更日志

> 跨交易所套利模块的版本历史

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 版本历史

### v0.7.0 (计划中)

**计划发布**: TBD

**新增功能**:
- [ ] CrossExchangeArbitrage 主策略
- [ ] 套利机会检测 (detectOpportunity)
- [ ] 净利润计算 (calculateNetProfit)
- [ ] 同步/顺序执行模式
- [ ] 风险控制 (仓位限制、冷却时间)
- [ ] 套利统计

**API 变更**:
- 新增 `CrossExchangeArbitrage` 结构
- 新增 `ArbitrageConfig` 配置
- 新增 `ArbitrageOpportunity` 结构
- 新增 `ExecutionResult` 结构

**依赖**:
- Clock-Driven (Story 033)
- SQLite Storage (Story 036)

---

## 计划中的改进

### v0.8.0+

- 三角套利支持
- 统计套利
- 多交易对并行套利
- 历史套利分析

---

## 变更日志格式

```markdown
### vX.Y.Z (YYYY-MM-DD)

**新增**:
- 功能描述

**修改**:
- 变更描述

**修复**:
- Bug 修复描述

**移除**:
- 删除的功能

**性能**:
- 性能优化描述

**文档**:
- 文档更新
```

---

*Last updated: 2025-12-27*
