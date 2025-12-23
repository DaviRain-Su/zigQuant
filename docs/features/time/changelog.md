# Time - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-01-22

---

## [0.1.0] - 2025-01-22

### Added

- ✨ 初始版本发布
- ✨ `Timestamp` 类型：毫秒精度 Unix 时间戳
- ✨ `Duration` 类型：时间间隔表示
- ✨ `KlineInterval` 枚举：支持 8 种常用 K线间隔 (1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w)
- ✨ ISO 8601 格式支持：`fromISO8601()` 和 `toISO8601()`
- ✨ K线时间对齐：`alignToKline()` 和 `isInSameKline()`
- ✨ 时间运算：`add()`, `sub()`, `diff()`
- ✨ 时间比较：`cmp()`, `eql()`
- ✨ Duration 常量：`ZERO`, `SECOND`, `MINUTE`, `HOUR`, `DAY`
- ✨ 完整的单元测试覆盖（100%）
- ✨ 边界测试和集成测试
- ✨ 性能基准测试

### Technical Details

- 基于 `i64` 整数，零成本抽象
- K线对齐算法：`aligned = floor(timestamp / interval) * interval`
- ISO 8601 解析：使用 Gregorian 日历算法
- 所有时间统一使用 UTC 时区

---

## [Unreleased]

### Planned

- [ ] 支持 RFC 3339 时间格式
- [ ] 添加 `TimeRange` 类型（时间范围）
- [ ] 支持纳秒精度（可选）
- [ ] 添加更多 K线间隔（如 2h, 6h, 12h）
- [ ] 时区转换支持（可选）
- [ ] 自然语言时间解析（如 "1 hour ago"）
- [ ] SIMD 优化批量时间处理

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)：

- **MAJOR**: 不兼容的 API 变更
- **MINOR**: 向后兼容的功能新增
- **PATCH**: 向后兼容的 Bug 修复

---

## 变更类型说明

- **Added**: 新增功能
- **Changed**: 功能变更
- **Deprecated**: 即将废弃的功能
- **Removed**: 已移除的功能
- **Fixed**: Bug 修复
- **Security**: 安全相关修复

---

*Last updated: 2025-01-22*
