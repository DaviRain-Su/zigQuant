# Error System - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-01-22

---

## [0.1.0] - 2025-01-22

### Added

- ✨ 初始版本发布
- ✨ 5 大错误类别：`NetworkError`, `APIError`, `DataError`, `BusinessError`, `SystemError`
- ✨ `ErrorContext` 结构：包含错误码、消息、位置、详情、时间戳
- ✨ `WrappedError` 结构：支持错误包装和错误链
- ✨ `wrap()` 函数：包装错误并添加上下文
- ✨ `wrapWithSource()` 函数：包装错误并设置源错误
- ✨ `unwind()` 方法：展开完整错误链
- ✨ 重试机制：`retry()` 函数支持自动重试
- ✨ 重试策略：固定间隔 (`fixed_interval`) 和指数退避 (`exponential_backoff`)
- ✨ `RetryConfig` 配置：支持最大重试次数、初始延迟、最大延迟
- ✨ `isRetriable()` 函数：判断错误是否可重试
- ✨ `isTemporary()` 函数：判断错误是否是临时错误
- ✨ 完整的单元测试覆盖（100%）
- ✨ 集成测试和边界测试
- ✨ 性能基准测试

### Technical Details

- 使用 Zig 的错误联合类型实现类型安全
- 错误链使用链表结构（`WrappedError.source`）
- 重试机制支持指数退避，最大延迟可配置
- 所有错误分类可通过 `||` 组合成统一错误集

---

## [Unreleased]

### Planned

- [ ] 错误链内存管理优化（Arena Allocator）
- [ ] 支持更多重试策略（抖动、自适应延迟）
- [ ] 添加自定义重试条件函数
- [ ] 错误聚合支持（`ErrorList`）
- [ ] 错误统计和监控
- [ ] 错误恢复策略（fallback）
- [ ] 错误国际化（i18n）
- [ ] 错误序列化（JSON/TOML）

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
