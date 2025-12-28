# AI 模块 - 变更日志

> 版本历史和更新记录

**模块路径**: `src/ai/`
**当前版本**: v0.9.0
**最后更新**: 2025-12-28

---

## [0.9.0] - 2025-12-28

### Added

- ✨ **ILLMClient 接口** - VTable 模式的 LLM 客户端抽象接口
  - `generateText()` - 文本生成
  - `generateObject()` - 结构化输出 (JSON Schema)
  - `getModel()` - 获取模型信息
  - `isConnected()` - 连接状态检查
  - `deinit()` - 资源释放

- ✨ **LLMClient 实现** - 多提供商 LLM 客户端
  - OpenAI 支持 (GPT-4o, o1, o3)
  - Anthropic 支持 (Claude Sonnet 4.5, Opus 4.5, Haiku)
  - 可配置的 max_tokens、temperature、timeout

- ✨ **AIAdvisor** - AI 交易建议服务
  - 结构化 AIAdvice 响应
  - 置信度评分 [0, 1]
  - 请求统计和延迟追踪
  - 可配置重试机制

- ✨ **PromptBuilder** - 市场分析 Prompt 构建器
  - 专业的市场数据格式化
  - 技术指标解读
  - 仓位上下文
  - JSON Schema 约束输出

- ✨ **HybridAIStrategy** - 混合决策策略
  - 技术指标与 AI 建议加权融合
  - 可配置权重 (默认: 技术 60%, AI 40%)
  - AI 失败时自动回退到纯技术指标
  - 完整 IStrategy 接口实现

- ✨ **类型定义**
  - `AIProvider` - AI 提供商枚举
  - `AIModel` - AI 模型信息
  - `AIConfig` - AI 配置
  - `AIAdvice` - 交易建议
  - `MarketContext` - 市场上下文
  - `IndicatorSnapshot` - 指标快照

- ✨ **Mock 实现** - 用于测试
  - `MockLLMClient` - 可配置响应和失败模拟

### Changed

- 🔄 无变更 (初始版本)

### Fixed

- 🐛 无修复 (初始版本)

### Deprecated

- ⚠️ 无弃用 (初始版本)

### Removed

- 🗑️ 无移除 (初始版本)

---

## [Unreleased]

### Planned

- [ ] Google Gemini 支持
- [ ] Ollama 本地模型支持
- [ ] 响应缓存机制
- [ ] 多模型投票决策
- [ ] 流式响应 (streamText)
- [ ] RAG (检索增强生成) 集成
- [ ] 模型 Fine-tuning 支持

### Under Consideration

- [ ] 自定义 Prompt 模板系统
- [ ] AI 模型性能对比工具
- [ ] 成本追踪和预算限制
- [ ] 批量请求优化
- [ ] 模型回退链配置

---

## 版本规范

遵循 [语义化版本](https://semver.org/lang/zh-CN/)：

- **MAJOR**: 不兼容的 API 变更
- **MINOR**: 向后兼容的功能新增
- **PATCH**: 向后兼容的 Bug 修复

---

## 变更类型

| 类型 | 描述 |
|------|------|
| ✨ Added | 新功能 |
| 🔄 Changed | 功能变更 |
| 🐛 Fixed | Bug 修复 |
| ⚠️ Deprecated | 即将移除 |
| 🗑️ Removed | 已移除 |
| 🔒 Security | 安全修复 |
| 📚 Documentation | 文档更新 |
| 🎨 Style | 代码格式 |
| ♻️ Refactor | 代码重构 |
| ⚡ Performance | 性能优化 |
| ✅ Test | 测试相关 |

---

## 迁移指南

### 从无到 v0.9.0

这是 AI 模块的首个版本，无需迁移。

要使用新模块：

```zig
const zigQuant = @import("zigQuant");

// 新的 AI 导入
const ILLMClient = zigQuant.ILLMClient;
const LLMClient = zigQuant.LLMClient;
const AIAdvisor = zigQuant.AIAdvisor;
const AIAdvice = zigQuant.AIAdvice;
const AIConfig = zigQuant.AIConfig;
const HybridAIStrategy = zigQuant.HybridAIStrategy;
const PromptBuilder = zigQuant.PromptBuilder;
```

### 依赖配置

确保 `build.zig.zon` 包含 `zig-ai-sdk`:

```zig
.@"zig-ai-sdk" = .{
    .url = "https://github.com/evmts/ai-zig/archive/refs/heads/master.tar.gz",
    .hash = "zig_ai_sdk-0.1.0-ULWwFOjsNQDpPPJBPUBUJKikJkiIAASwHYLwqyzEmcim",
},
```

### 环境变量

```bash
# OpenAI
export OPENAI_API_KEY="sk-..."

# Anthropic
export ANTHROPIC_API_KEY="sk-ant-..."
```

---

## 发布历史

| 版本 | 日期 | 主要变更 |
|------|------|----------|
| v0.9.0 | 2025-12-28 | 初始版本 - AI 策略集成 |

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)
- [Bug 追踪](./bugs.md)
- [v0.9.0 Release Notes](../../releases/RELEASE_v0.9.0.md)

---

*最后更新: 2025-12-28*
