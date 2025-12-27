# SQLite Storage 变更日志

> 数据持久化模块的版本历史

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 版本历史

### v0.7.0 (计划中)

**计划发布**: TBD

**新增功能**:
- [ ] DataStore 核心结构
- [ ] K 线数据存储 (storeCandles/loadCandles)
- [ ] 回测结果存储 (storeBacktestResult/loadBacktestResults)
- [ ] 交易记录存储
- [ ] CandleCache 内存缓存
- [ ] 增量更新 (getLatestTimestamp)
- [ ] WAL 模式支持

**API 变更**:
- 新增 `DataStore` 结构
- 新增 `CandleCache` 结构
- 新增 `StorageConfig` 配置
- 新增 `BacktestResultStore` 结构

**依赖**:
- zig-sqlite 库

---

## 计划中的改进

### v0.8.0+

- 数据压缩存储
- 自动数据清理策略
- 远程数据库支持
- 数据导入/导出工具

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
