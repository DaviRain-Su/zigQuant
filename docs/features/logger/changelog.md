# Logger - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-01-22

---

## [0.1.0] - 2025-01-22

### Added

- ✨ 初始版本发布
- ✨ 6 个日志级别：trace, debug, info, warn, error, fatal
- ✨ 结构化日志支持（键值对字段）
- ✨ `Logger` 核心类型
- ✨ `LogWriter` 接口（vtable 模式）
- ✨ `ConsoleWriter`: 控制台输出
- ✨ `FileWriter`: 文件输出
- ✨ `JSONWriter`: JSON 格式输出
- ✨ `RotatingFileWriter`: 自动轮转文件输出
- ✨ 日志级别过滤（零分配快速路径）
- ✨ 编译时字段转换
- ✨ 线程安全（Mutex 保护）
- ✨ 完整的单元测试覆盖
- ✨ 性能基准测试

### Technical Details

- 使用 vtable 模式实现可扩展 Writer
- 编译时类型推导和字段转换
- 级别过滤提前返回，避免不必要分配
- 所有 Writer 使用 Mutex 保证线程安全

---

## [Unreleased]

### Planned

- [ ] 异步日志（后台线程）
- [ ] JSON 字符串完整转义
- [ ] 日志采样（高频场景）
- [ ] 日志压缩（gzip）
- [ ] 远程日志（HTTP/gRPC）
- [ ] 日志聚合（多个 Logger）
- [ ] 结构化查询
- [ ] 日志归档策略

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)

---

*Last updated: 2025-01-22*
