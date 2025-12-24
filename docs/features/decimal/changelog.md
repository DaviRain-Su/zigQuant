# Decimal - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-24

---

## [0.1.0] - 2025-12-24 ✅

### Added
- ✨ 初始实现 Decimal 类型
- ✨ 基本四则运算 (add, sub, mul, div)
- ✨ 比较操作 (cmp, eql)
- ✨ 构造函数 (fromInt, fromFloat, fromString)
- ✨ 转换函数 (toFloat, toString)
- ✨ 常量 (ZERO, ONE, SCALE, MULTIPLIER)
- ✨ 工具函数 (abs, negate, isZero, isPositive, isNegative)
- ✨ 错误处理 (DivisionByZero, EmptyString, InvalidFormat, InvalidCharacter, MultipleDecimalPoints)

### Implementation Details
- 🔧 基于 i128 整数 + 固定 18 位小数精度
- 🔧 使用 i256 中间类型处理乘除法，防止溢出
- 🔧 整数运算，无浮点误差
- 🔧 字符串解析支持多种格式（整数、小数、带符号）

### Documentation
- 📝 完整的 API 文档 (api.md)
- 📝 实现细节说明 (implementation.md)
- 📝 测试覆盖文档 (testing.md)
- 📝 使用示例和最佳实践 (README.md)
- 📝 更新至 Zig 0.15.2 语法

### Testing
- ✅ 12 单元测试全部通过
- ✅ 覆盖构造、运算、比较、转换、工具函数
- ✅ 精度验证测试（0.1 + 0.2 = 0.3）
- ✅ 错误处理测试

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
