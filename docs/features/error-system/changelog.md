# Error System - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-23

---

## [0.1.0] - 2025-12-23

### Added

- ✨ 初始版本发布
- ✨ 5 大错误类别：`NetworkError` (4种), `APIError` (6种), `DataError` (5种), `BusinessError` (6种), `SystemError` (4种)
- ✨ 组合错误集：`TradingError` = 所有错误类别的联合
- ✨ `ErrorContext` 结构：包含错误码、消息、位置、详情、时间戳
  - `init(message)` 方法：自动添加时间戳
  - `initWithCode(code, message)` 方法：带错误码的构造
  - `format(writer)` 方法：格式化输出（支持 `{f}` 格式符）
- ✨ `WrappedError` 结构：支持错误包装和错误链
  - `init(err, context)` 方法：创建包装错误
  - `initWithSource(err, context, source)` 方法：创建错误链
  - `chainDepth()` 方法：获取错误链深度
  - `printChain(writer)` 方法：打印完整错误链
- ✨ 错误包装函数：
  - `wrap(err, message)` - 简单包装
  - `wrapWithCode(err, code, message)` - 带错误码包装
  - `wrapWithSource(err, message, source)` - 创建错误链
- ✨ 重试机制：`retry()` 函数支持自动重试
  - 返回类型自动推导：`@TypeOf(@call(.auto, func, args))`
  - 使用 `std.Thread.sleep()` 进行延迟
- ✨ 重试策略：固定间隔 (`fixed_interval`) 和指数退避 (`exponential_backoff`)
- ✨ `RetryConfig` 配置：支持最大重试次数、初始延迟、最大延迟
  - `calculateDelay(attempt)` 方法：计算重试延迟时间
- ✨ `isRetryable()` 函数：判断错误是否可重试（6种可重试错误）
- ✨ `errorCategory()` 函数：获取错误类别名称（使用编译时反射）
- ✨ 完整的单元测试覆盖（11/11 测试通过，100%）
- ✨ 集成测试：错误链、重试机制、延迟计算
- ✨ Demo 程序演示所有功能

### Technical Details

- **类型系统**：使用 Zig 的错误联合类型 (`error{}`) 实现类型安全
- **错误链**：使用链表结构（`source: ?*const WrappedError`）形成错误链
- **重试机制**：
  - 使用 `std.Thread.sleep()` 进行延迟（Zig 0.15）
  - 返回类型通过 `@TypeOf(@call(.auto, func, args))` 自动推导
  - 指数退避算法：`delay = initial * 2^attempt`，上限为 `max_delay_ms`
- **错误分类**：使用 `||` 组合成 `TradingError` 统一错误集
- **错误分类识别**：使用 `@typeInfo()` 编译时反射遍历错误集
- **格式化输出**：ErrorContext 实现 `format(writer)` 方法，支持 Zig 0.15 的 `{f}` 格式符
- **零成本抽象**：ErrorContext 和 WrappedError 都是值类型，在栈上分配
- **测试覆盖**：11 个单元测试，覆盖所有核心功能

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

*Last updated: 2025-12-23*
