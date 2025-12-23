# Config - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-01-22

---

## [0.1.0] - 2025-01-22

### Added

- ✨ 初始版本发布
- ✨ `ConfigLoader` 核心类型
- ✨ JSON 格式支持
- ✨ TOML 格式支持
- ✨ 环境变量覆盖（ZIGQUANT_* 前缀）
- ✨ 配置验证机制
- ✨ 敏感信息保护（sanitize）
- ✨ `AppConfig`, `ServerConfig`, `ExchangeConfig`, `TradingConfig`, `LoggingConfig`
- ✨ 优先级加载（默认 → 文件 → 环境变量）
- ✨ 完整的单元测试覆盖

### Technical Details

- 使用编译时类型检查
- 环境变量自动映射到配置字段
- 敏感信息在日志中自动隐藏

---

## [Unreleased]

### Planned

- [ ] YAML 格式支持
- [ ] 配置热更新
- [ ] 配置加密（AES）
- [ ] 远程配置中心
- [ ] 配置版本管理
- [ ] 配置 diff 工具
- [ ] 配置模板

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)

---

*Last updated: 2025-01-22*
