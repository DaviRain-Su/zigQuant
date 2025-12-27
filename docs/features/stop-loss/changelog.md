# StopLoss - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-27

---

## [Unreleased]

### Planned

- [ ] StopLossManager 核心实现
- [ ] 固定止损/止盈
- [ ] 百分比跟踪止损
- [ ] 固定距离跟踪止损
- [ ] 时间止损
- [ ] 部分平仓支持
- [ ] 与策略系统集成
- [ ] 单元测试套件

---

## [0.8.0] - 计划中

### Added

- ✨ StopLossManager 核心结构
- ✨ 止损设置功能
  - `setStopLoss`: 固定止损
  - `setTakeProfit`: 固定止盈
  - `setTrailingStopPct`: 百分比跟踪止损
  - `setTrailingStopDistance`: 固定距离跟踪止损
- ✨ 检查执行功能
  - `checkAndExecute`: 检查并触发止损
- ✨ 管理功能
  - `cancelStopLoss`: 取消止损
  - `cancelTakeProfit`: 取消止盈
  - `cancelTrailingStop`: 取消跟踪止损
  - `removeAll`: 移除所有设置
- ✨ 统计功能
  - `getStats`: 获取触发统计

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)
