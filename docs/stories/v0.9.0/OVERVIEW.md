# v0.9.0 - AI 策略集成

**版本**: 0.9.0
**代号**: AI-Powered Trading
**状态**: 开发中
**计划日期**: 2025-01

---

## 版本概述

v0.9.0 引入 AI 辅助交易决策能力，通过 `zig-ai-sdk` 集成多个 LLM 提供商（OpenAI、Anthropic Claude 等），实现传统技术分析与 AI 智能分析的混合决策系统。

### 核心价值

1. **智能决策增强** - AI 分析市场数据，提供交易建议
2. **多模型支持** - 统一接口支持 30+ AI 提供商
3. **混合策略** - 结合技术指标和 AI 建议的加权决策
4. **容错设计** - AI 失败时自动回退到纯技术指标

---

## 核心组件

### 1. ILLMClient - LLM 客户端抽象接口

VTable 模式的 LLM 客户端接口，与项目现有架构（IStrategy, IExchange）保持一致。

```zig
pub const ILLMClient = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        generateText: *const fn (ptr: *anyopaque, prompt: []const u8) anyerror![]const u8,
        generateObject: *const fn (ptr: *anyopaque, prompt: []const u8, schema: []const u8) anyerror![]const u8,
        getModel: *const fn (ptr: *anyopaque) AIModel,
        isConnected: *const fn (ptr: *anyopaque) bool,
        deinit: *const fn (ptr: *anyopaque) void,
    };
};
```

### 2. LLMClient - 多提供商客户端

基于 `zig-ai-sdk` 的具体实现，支持：

- **OpenAI** - GPT-4o, GPT-4, o1, o3 系列
- **Anthropic** - Claude Sonnet 4.5, Opus 4.5, Haiku
- **Google** - Gemini 系列 (规划中)
- **自定义** - 可扩展接口

### 3. AIAdvisor - AI 交易建议服务

封装 LLM 调用，提供结构化交易建议：

```zig
pub const AIAdvice = struct {
    action: Action,        // strong_buy, buy, hold, sell, strong_sell
    confidence: f64,       // [0.0, 1.0] 置信度
    reasoning: []const u8, // AI 解释
    timestamp: i64,
};
```

### 4. PromptBuilder - Prompt 构建器

专业的市场分析 Prompt 工程：

- 市场数据格式化
- 技术指标解读
- 仓位上下文
- JSON Schema 结构化输出

### 5. HybridAIStrategy - 混合决策策略

结合技术指标和 AI 建议的加权决策：

```
综合得分 = 技术权重 × 技术得分 + AI 权重 × AI 得分
```

- 可配置权重分配（默认：技术 60%, AI 40%）
- AI 失败时自动回退到纯技术指标
- 完整的 IStrategy 接口实现

---

## Stories

### Story 046: AI 策略集成

**优先级**: P1
**状态**: 开发中
**文档**: [STORY_046_AI_STRATEGY.md](./STORY_046_AI_STRATEGY.md)

#### 验收标准

- [ ] ILLMClient 接口 (VTable 模式)
- [ ] OpenAI/Anthropic 客户端实现
- [ ] AIAdvisor 结构化交易建议
- [ ] HybridAIStrategy 混合策略
- [ ] 完整单元测试
- [ ] 示例代码

---

## 依赖

### zig-ai-sdk

```zig
// build.zig.zon
.@"zig-ai-sdk" = .{
    .url = "https://github.com/evmts/ai-zig/archive/refs/heads/master.tar.gz",
    .hash = "zig_ai_sdk-0.1.0-ULWwFOjsNQDpPPJBPUBUJKikJkiIAASwHYLwqyzEmcim",
},
```

**核心 API**:
- `ai.generateText()` - 文本生成
- `ai.generateObject()` - 结构化输出 (JSON Schema)
- `ai.streamText()` - 流式响应
- 支持 30+ AI 提供商

### 环境变量

```bash
# OpenAI
export OPENAI_API_KEY="sk-..."

# Anthropic
export ANTHROPIC_API_KEY="sk-ant-..."

# Google (规划中)
export GOOGLE_AI_API_KEY="..."
```

---

## 文件结构

```
src/ai/
├── mod.zig              # 模块导出
├── types.zig            # AI 相关类型定义
├── interfaces.zig       # ILLMClient 接口定义
├── client.zig           # 通用 LLM 客户端
├── advisor.zig          # AI Advisor 辅助决策
└── prompt_builder.zig   # Prompt 构建器

src/strategy/builtin/
└── hybrid_ai.zig        # HybridAIStrategy 混合策略

examples/
└── 32_ai_strategy.zig   # AI 策略示例
```

---

## 使用示例

### 基础用法

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 配置 AI
    const ai_config = zigQuant.AIConfig{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
        .api_key = std.posix.getenv("ANTHROPIC_API_KEY") orelse return error.NoApiKey,
        .temperature = 0.3,
    };

    // 2. 创建 Hybrid 策略
    const strategy = try zigQuant.HybridAIStrategy.create(allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .timeframe = .h1,
        .ai_weight = 0.4,        // AI 权重 40%
        .technical_weight = 0.6, // 技术权重 60%
        .ai_config = ai_config,
    });
    defer strategy.destroy();

    // 3. 回测
    const engine = try zigQuant.BacktestEngine.init(allocator, .{});
    defer engine.deinit();

    const result = try engine.run(strategy.toStrategy(), candles);

    std.debug.print("AI Hybrid Strategy Results:\n", .{});
    std.debug.print("  Total Return: {d:.2}%\n", .{result.total_return * 100});
    std.debug.print("  Sharpe Ratio: {d:.2}\n", .{result.sharpe_ratio});
}
```

### 单独使用 AIAdvisor

```zig
// 创建 LLM 客户端
const client = try zigQuant.LLMClient.init(allocator, .{
    .provider = .openai,
    .model_id = "gpt-4o",
    .api_key = api_key,
});
defer client.deinit();

// 创建 Advisor
var advisor = zigQuant.AIAdvisor.init(allocator, client.toInterface(), .{});
defer advisor.deinit();

// 获取建议
const ctx = zigQuant.MarketContext{
    .pair = .{ .base = "BTC", .quote = "USDT" },
    .current_price = Decimal.fromFloat(45000.0),
    .price_change_24h = 0.025, // +2.5%
    .indicators = &.{
        .{ .name = "RSI", .value = 35.5, .interpretation = "approaching oversold" },
        .{ .name = "MACD", .value = 120.3, .interpretation = "bullish momentum" },
    },
    .recent_candles = candles,
    .position = null,
};

const advice = try advisor.getAdvice(ctx);
std.debug.print("AI Advice: {s} (confidence: {d:.0}%)\n", .{
    @tagName(advice.action),
    advice.confidence * 100,
});
std.debug.print("Reasoning: {s}\n", .{advice.reasoning});
```

---

## 性能考虑

### 延迟

- AI API 调用延迟：500ms - 5s（取决于模型和网络）
- 本地技术指标计算：< 1ms
- 建议：高频策略应减少 AI 权重或增加调用间隔

### 成本

- OpenAI GPT-4o: ~$5/1M tokens
- Anthropic Claude Sonnet: ~$3/1M tokens
- 建议：设置 `max_tokens` 限制，使用缓存

### 容错

- AI 调用失败自动回退到纯技术指标
- 可配置重试次数和超时
- 请求统计和延迟追踪

---

## 与 v0.8.0 的关系

v0.9.0 建立在 v0.8.0 风险管理基础之上：

- **RiskEngine** 可用于限制 AI 策略的仓位大小
- **StopLoss** 保护 AI 决策的潜在错误
- **AlertSystem** 可发送 AI 决策通知

---

## 未来扩展

### v0.10.0+ 规划

1. **多模型投票** - 多个 AI 模型投票决策
2. **Fine-tuning** - 针对交易场景微调
3. **RAG 集成** - 检索增强生成
4. **本地模型** - 支持 Ollama 等本地模型

---

## 相关文档

- [Story 046: AI 策略集成](./STORY_046_AI_STRATEGY.md)
- [AI 模块 API](../../features/ai/README.md)
- [实现细节](../../features/ai/implementation.md)
- [Release Notes](../../releases/RELEASE_v0.9.0.md)

---

*最后更新: 2025-12-28*
