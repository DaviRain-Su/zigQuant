# Decimal - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-01-22

---

## [0.1.0] - 2025-01-22 ✅

### Added
- ✨ 初始实现 Decimal 类型
- ✨ 基本四则运算 (add, sub, mul, div)
- ✨ 比较操作 (cmp, eql)
- ✨ 字符串转换 (fromString, toString)
- ✨ 常量 (ZERO, ONE)
- ✨ 工具函数 (abs, negate, isZero, isPositive, isNegative)

### Fixed
- 🐛 修复除法精度丢失问题 (#1)

### Documentation
- 📝 完整的 API 文档
- 📝 实现细节说明
- 📝 测试覆盖文档
- 📝 使用示例

### Testing
- ✅ 15+ 单元测试
- ✅ 97% 代码覆盖率
- ✅ 性能基准测试

---

## [Unreleased]

### Planned
- [ ] 可配置精度支持
- [ ] 更多数学函数 (sqrt, pow, round)
- [ ] 货币格式化功能
- [ ] JSON 序列化/反序列化
- [ ] SIMD 优化
- [ ] 不同舍入模式支持

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)：

- **MAJOR**: 不兼容的 API 变更
- **MINOR**: 向后兼容的功能新增
- **PATCH**: 向后兼容的 Bug 修复

---

## 变更类型

- `Added`: 新功能
- `Changed`: 现有功能变更
- `Deprecated`: 即将移除的功能
- `Removed`: 已移除的功能
- `Fixed`: Bug 修复
- `Security`: 安全性修复
