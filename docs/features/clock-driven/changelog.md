# Clock-Driven - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-27

---

## [Unreleased]

### Planned
- [ ] Clock 核心结构实现
- [ ] IClockStrategy 接口定义
- [ ] Tick 精度优化 (< 10ms 抖动)
- [ ] 策略注册/注销管理
- [ ] 与 MessageBus 集成
- [ ] 与 Paper Trading 集成
- [ ] 完整单元测试和性能基准

---

## [0.7.0] - 待发布

### Added
- Clock 时钟驱动调度器
- IClockStrategy 策略接口
- ClockStats 统计信息
- 纳秒级 tick 精度
- 多策略并发执行
- 原子状态管理

### Features
- 支持毫秒级 tick 间隔配置
- 策略 onTick/onStart/onStop 生命周期
- Tick 超时检测和警告
- 运行时统计 (tick 计数、平均/最大耗时)

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)：

- **MAJOR**: 不兼容的 API 变更
- **MINOR**: 向后兼容的功能新增
- **PATCH**: 向后兼容的 Bug 修复

---

## 路线图

### v0.7.x
- 基础 Clock 实现
- IClockStrategy 接口
- 核心功能测试

### v0.8.x (未来)
- 可变 tick 间隔支持
- 策略优先级
- 与 libxev 事件循环集成

### v1.0.x (未来)
- 分布式时钟同步
- 多交易所时钟协调

---

*Last updated: 2025-12-27*
