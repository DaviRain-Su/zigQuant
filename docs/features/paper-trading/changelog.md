# Paper Trading 变更日志

本文档记录 Paper Trading 模块的所有重要变更。

---

## [未发布] - v0.6.0

### 计划功能

- **PaperTradingEngine**: 主引擎，协调数据、策略和执行
- **SimulatedExecutor**: 模拟订单执行，包含滑点和手续费
- **SimulatedAccount**: 模拟账户余额和仓位管理
- **实时统计**: PnL、胜率、回撤等指标实时计算
- **CLI 集成**: `zigquant run-strategy --paper` 命令

### 性能目标

- 数据延迟: < 10ms
- 模拟精度: > 99%
- 内存占用: < 50MB
- 统计准确性: 100%

---

## 版本规范

- **Major**: 不兼容的 API 变更
- **Minor**: 向后兼容的功能新增
- **Patch**: 向后兼容的 bug 修复

---

*Last updated: 2025-12-27*
