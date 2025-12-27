# Inventory Management 变更日志

> 库存管理模块的版本历史

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 版本历史

### v0.7.0 (计划中)

**计划发布**: TBD

**新增功能**:
- [ ] InventoryManager 核心结构
- [ ] 三种偏斜模式 (linear/exponential/tiered)
- [ ] adjustQuotes 报价调整
- [ ] 再平衡机制
- [ ] 紧急状态处理
- [ ] 库存统计

**API 变更**:
- 新增 `InventoryManager` 结构
- 新增 `InventoryConfig` 配置
- 新增 `SkewMode` 枚举
- 新增 `RebalanceAction` 结构

**依赖**:
- Pure Market Making (Story 034)

---

## 计划中的改进

### v0.8.0+

- 自适应偏斜系数
- 多资产库存管理
- 历史库存分析
- 库存预测模型

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
