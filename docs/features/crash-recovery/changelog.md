# CrashRecovery - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-27

---

## [Unreleased]

### Planned

- [ ] RecoveryManager 核心实现
- [ ] StateStore 检查点存储
- [ ] 序列化/反序列化
- [ ] 交易所同步
- [ ] 定期检查点
- [ ] 检查点清理

---

## [0.8.0] - 计划中

### Added

- ✨ RecoveryManager 核心结构
- ✨ 检查点功能
  - `checkpoint`: 创建检查点
  - `checkpointOnTrade`: 交易后检查点
  - `startPeriodicCheckpoint`: 定期检查点
- ✨ 恢复功能
  - `recover`: 从检查点恢复
  - `autoRecover`: 自动恢复
- ✨ 同步功能
  - `syncWithExchange`: 交易所同步
- ✨ 管理功能
  - 检查点清理
  - 统计信息

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)
