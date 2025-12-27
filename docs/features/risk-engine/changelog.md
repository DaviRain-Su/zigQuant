# RiskEngine - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-27

---

## [Unreleased]

### Planned

- [ ] RiskEngine 核心实现
- [ ] RiskConfig 配置结构
- [ ] 仓位大小检查
- [ ] 杠杆检查
- [ ] 日损失检查
- [ ] 订单频率检查
- [ ] Kill Switch 功能
- [ ] 与 ExecutionEngine 集成
- [ ] 与 AlertManager 集成
- [ ] 单元测试套件
- [ ] 性能基准测试

---

## [0.8.0] - 计划中

### Added

- ✨ RiskEngine 核心结构
  - 初始化和资源管理
  - 配置验证

- ✨ 风控检查功能
  - `checkOrder`: 订单风控检查
  - `checkPositionSize`: 仓位大小检查
  - `checkLeverage`: 杠杆检查
  - `checkDailyLoss`: 日损失检查
  - `checkOrderRate`: 订单频率检查
  - `checkAvailableMargin`: 保证金检查

- ✨ Kill Switch 功能
  - `killSwitch`: 紧急停止交易
  - `resetKillSwitch`: 重置 Kill Switch
  - `checkKillSwitchConditions`: 自动触发检查

- ✨ 配置选项
  - `RiskConfig.default()`: 默认配置
  - `RiskConfig.conservative()`: 保守配置

- ✨ 统计功能
  - `getStats`: 获取风控统计
  - 检查次数统计
  - 拒绝订单统计

### Changed

*首次发布，无变更*

### Fixed

*首次发布，无修复*

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)：

- **MAJOR**: 不兼容的 API 变更
- **MINOR**: 向后兼容的功能新增
- **PATCH**: 向后兼容的 Bug 修复

---

## 里程碑

| 版本 | 状态 | 日期 | 描述 |
|------|------|------|------|
| v0.8.0 | 📋 规划中 | TBD | 初始实现 |
| v0.9.0 | 📋 规划中 | TBD | 多账户支持 |
| v1.0.0 | 📋 规划中 | TBD | 生产就绪 |
