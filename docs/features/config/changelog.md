# Config - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-24

---

## [0.2.0] - 2025-12-24

### Changed

- 📝 更新文档以反映实际实现
- 📝 明确 TOML 支持状态（未实现）
- 📝 更正 API 签名和使用示例
- 📝 添加详细的验证规则说明
- 📝 添加环境变量命名规则文档

### Documentation

- 更新所有代码示例使用 Zig 0.15.2 语法
- 明确 `loadFromJSON` 返回 `std.json.Parsed(T)`
- 说明 `ExchangeConfig.sanitize()` 不需要 allocator
- 说明 `AppConfig.sanitize()` 需要 allocator 并需手动释放
- 添加 `ConfigError` 错误类型文档
- 添加所有配置类型的默认值文档

---

## [0.1.0] - 2025-01-22

### Added

- ✨ 初始版本发布
- ✨ `ConfigLoader` 核心类型
- ✨ JSON 格式完整支持
- ⚠️ TOML 格式声明但未实现（返回 error.UnsupportedFormat）
- ✨ 环境变量覆盖（ZIGQUANT_* 前缀）
  - 支持按索引覆盖数组元素
  - 支持按名称覆盖交易所配置
- ✨ 配置验证机制（10 种验证规则）
- ✨ 敏感信息保护（sanitize）
- ✨ `AppConfig`, `ServerConfig`, `ExchangeConfig`, `TradingConfig`, `LoggingConfig`
- ✨ 优先级加载（默认 → 文件 → 环境变量）
- ✨ 多交易所配置支持
- ✨ 完整的单元测试覆盖

### Technical Details

- 使用 Zig 0.15.2
- 使用编译时类型检查（`@hasDecl`, `@typeInfo`）
- 环境变量自动映射到配置字段
- 敏感信息在日志中自动隐藏
- 返回 `std.json.Parsed(T)` 对象管理内存

---

## [Unreleased]

### Planned

- [ ] TOML 格式支持（当前返回 error.UnsupportedFormat）
- [ ] YAML 格式支持
- [ ] 配置热更新（文件监听）
- [ ] 配置加密（AES）
- [ ] 远程配置中心集成
- [ ] 配置版本管理
- [ ] 配置 diff 工具
- [ ] 配置模板系统
- [ ] 修复 `load()` 方法返回类型问题（应返回 `Parsed(T)` 而非 `T`）
- [ ] 添加枚举类型的环境变量支持
- [ ] 补充完整的错误验证测试

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)

---

*Last updated: 2025-12-24*
