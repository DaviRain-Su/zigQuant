# Dual Latency 变更日志

> 双向延迟模拟模块的版本历史

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 版本历史

### v0.7.0 (计划中)

**计划发布**: TBD

**新增功能**:
- [ ] LatencySimulator 主结构
- [ ] 3 种延迟模型 (Constant/Normal/Interpolated)
- [ ] FeedLatencyModel 行情延迟
- [ ] OrderLatencyModel 订单延迟
- [ ] OrderTimeline 时间线
- [ ] 延迟统计

**API 变更**:
- 新增 `LatencySimulator` 结构
- 新增 `LatencyModel` 结构
- 新增 `LatencyModelType` 枚举
- 新增 `OrderTimeline` 结构
- 新增 `LatencyStats` 结构

**依赖**:
- Queue Position (Story 038)

---

## 计划中的改进

### v0.8.0+

- 时变延迟模型
- 延迟相关性模拟
- 延迟尖峰模拟
- 延迟可视化工具

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
