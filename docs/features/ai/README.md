# AI 模块

**版本**: v0.9.0
**模块路径**: `src/ai/`
**状态**: 开发中

---

## 概述

ZigQuant AI 模块提供 LLM (大语言模型) 集成能力，支持 AI 辅助交易决策。通过统一的 `ILLMClient` 接口抽象，可以无缝切换不同的 AI 提供商（OpenAI、Anthropic Claude 等）。

### 核心特性

- **多提供商支持** - 统一接口支持 30+ AI 提供商
- **结构化输出** - JSON Schema 约束的结构化响应
- **混合决策** - 技术指标与 AI 建议加权融合
- **容错设计** - AI 失败时自动回退到纯技术指标

---

## 快速开始

### 1. 配置环境变量

```bash
# OpenAI
export OPENAI_API_KEY="sk-..."

# Anthropic Claude
export ANTHROPIC_API_KEY="sk-ant-..."
```

### 2. 基础用法

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
        .max_tokens = 1024,
    };

    // 2. 创建 LLM 客户端
    const client = try zigQuant.LLMClient.init(allocator, ai_config);
    defer client.deinit();

    // 3. 生成文本响应
    const response = try client.toInterface().generateText(
        "Analyze BTC/USDT market conditions and provide a trading recommendation."
    );
    defer allocator.free(response);

    std.debug.print("AI Response: {s}\n", .{response});
}
```

### 3. 使用 AIAdvisor

```zig
// 创建 Advisor
var advisor = zigQuant.AIAdvisor.init(allocator, client.toInterface(), .{
    .min_confidence_threshold = 0.6,
    .max_retries = 2,
});
defer advisor.deinit();

// 构建市场上下文
const ctx = zigQuant.MarketContext{
    .pair = .{ .base = "BTC", .quote = "USDT" },
    .current_price = zigQuant.Decimal.fromFloat(45000.0),
    .price_change_24h = 0.025, // +2.5%
    .indicators = &.{
        .{ .name = "RSI", .value = 35.5, .interpretation = "approaching oversold" },
        .{ .name = "MACD", .value = 120.3, .interpretation = "bullish momentum" },
    },
    .recent_candles = candles,
    .position = null,
};

// 获取 AI 建议
const advice = try advisor.getAdvice(ctx);
std.debug.print("Action: {s}, Confidence: {d:.0}%\n", .{
    @tagName(advice.action),
    advice.confidence * 100,
});
std.debug.print("Reasoning: {s}\n", .{advice.reasoning});
```

### 4. 使用 HybridAIStrategy

```zig
// 创建混合策略
const strategy = try zigQuant.HybridAIStrategy.create(allocator, .{
    .pair = .{ .base = "BTC", .quote = "USDT" },
    .timeframe = .h1,
    .ai_weight = 0.4,        // AI 权重 40%
    .technical_weight = 0.6, // 技术权重 60%
    .ai_config = ai_config,
});
defer strategy.destroy();

// 用于回测
const engine = try zigQuant.BacktestEngine.init(allocator, .{});
defer engine.deinit();

const result = try engine.run(strategy.toStrategy(), candles);
std.debug.print("Total Return: {d:.2}%\n", .{result.total_return * 100});
```

---

## 核心组件

### ILLMClient

LLM 客户端的 VTable 接口，提供统一的 API 调用方式。

```zig
pub const ILLMClient = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// 生成文本响应
        generateText: *const fn (ptr: *anyopaque, prompt: []const u8) anyerror![]const u8,

        /// 生成结构化响应 (JSON Schema)
        generateObject: *const fn (ptr: *anyopaque, prompt: []const u8, schema: []const u8) anyerror![]const u8,

        /// 获取模型信息
        getModel: *const fn (ptr: *anyopaque) AIModel,

        /// 检查连接状态
        isConnected: *const fn (ptr: *anyopaque) bool,

        /// 释放资源
        deinit: *const fn (ptr: *anyopaque) void,
    };

    // 便捷方法
    pub fn generateText(self: ILLMClient, prompt: []const u8) ![]const u8;
    pub fn generateObject(self: ILLMClient, prompt: []const u8, schema: []const u8) ![]const u8;
    pub fn getModel(self: ILLMClient) AIModel;
    pub fn isConnected(self: ILLMClient) bool;
    pub fn deinit(self: ILLMClient) void;
};
```

### LLMClient

多提供商 LLM 客户端实现。

```zig
pub const LLMClient = struct {
    allocator: std.mem.Allocator,
    config: AIConfig,
    provider: ProviderUnion,
    connected: bool,

    pub fn init(allocator: std.mem.Allocator, config: AIConfig) !*LLMClient;
    pub fn deinit(self: *LLMClient) void;
    pub fn toInterface(self: *LLMClient) ILLMClient;
};
```

**支持的提供商**:

| Provider | Model IDs | 特性 |
|----------|-----------|------|
| OpenAI | `gpt-4o`, `gpt-4`, `o1`, `o3` | 最新推理模型 |
| Anthropic | `claude-sonnet-4-5`, `claude-opus-4-5`, `claude-haiku` | 长上下文、推理能力 |
| Google | `gemini-pro`, `gemini-ultra` | (规划中) |

### AIAdvisor

封装 LLM 调用，提供结构化交易建议。

```zig
pub const AIAdvisor = struct {
    allocator: std.mem.Allocator,
    client: ILLMClient,
    prompt_builder: PromptBuilder,
    config: AdvisorConfig,

    // 统计
    total_requests: u64,
    successful_requests: u64,
    avg_latency_ms: f64,

    pub const AdvisorConfig = struct {
        min_confidence_threshold: f64 = 0.6,
        cache_ttl_seconds: u32 = 60,
        max_retries: u8 = 2,
    };

    pub fn init(allocator: std.mem.Allocator, client: ILLMClient, config: AdvisorConfig) AIAdvisor;
    pub fn deinit(self: *AIAdvisor) void;
    pub fn getAdvice(self: *AIAdvisor, ctx: MarketContext) !AIAdvice;
    pub fn getStats(self: *AIAdvisor) AdvisorStats;
};
```

### PromptBuilder

构建专业的市场分析 Prompt。

```zig
pub const PromptBuilder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) PromptBuilder;
    pub fn deinit(self: *PromptBuilder) void;
    pub fn buildMarketAnalysisPrompt(self: *PromptBuilder, ctx: MarketContext) ![]const u8;
    pub fn getAdviceSchema() []const u8;
};
```

### HybridAIStrategy

结合技术指标和 AI 建议的混合决策策略。

```zig
pub const HybridAIStrategy = struct {
    allocator: std.mem.Allocator,
    config: Config,
    indicator_manager: IndicatorManager,
    ai_advisor: *AIAdvisor,
    logger: Logger,
    initialized: bool,

    pub const Config = struct {
        pair: TradingPair,
        timeframe: Timeframe,

        // 技术指标参数
        rsi_period: u32 = 14,
        rsi_oversold: f64 = 30,
        rsi_overbought: f64 = 70,
        sma_period: u32 = 20,

        // AI 权重
        ai_weight: f64 = 0.4,        // [0, 1]
        technical_weight: f64 = 0.6,  // [0, 1]

        // 信号阈值
        min_combined_score: f64 = 0.6,

        // AI 配置
        ai_config: AIConfig,
    };

    pub fn create(allocator: std.mem.Allocator, config: Config) !*HybridAIStrategy;
    pub fn destroy(self: *HybridAIStrategy) void;
    pub fn toStrategy(self: *HybridAIStrategy) IStrategy;
};
```

**决策公式**:

```
综合得分 = technical_weight × 技术得分 + ai_weight × AI 得分
```

---

## 类型定义

### AIProvider

```zig
pub const AIProvider = enum {
    openai,
    anthropic,
    google,
    custom,
};
```

### AIModel

```zig
pub const AIModel = struct {
    provider: AIProvider,
    model_id: []const u8,  // "gpt-4o", "claude-sonnet-4-5", etc.
};
```

### AIConfig

```zig
pub const AIConfig = struct {
    provider: AIProvider,
    model_id: []const u8,
    api_key: []const u8,
    max_tokens: u32 = 1024,
    temperature: f32 = 0.3,    // 低温度更确定性
    timeout_ms: u32 = 30000,
};
```

### AIAdvice

```zig
pub const AIAdvice = struct {
    action: Action,
    confidence: f64,        // [0.0, 1.0]
    reasoning: []const u8,  // AI 解释
    timestamp: i64,

    pub const Action = enum {
        strong_buy,   // 强烈买入
        buy,          // 买入
        hold,         // 持有/观望
        sell,         // 卖出
        strong_sell,  // 强烈卖出
    };

    /// 转换为得分 [0, 1]
    pub fn toScore(self: AIAdvice) f64 {
        return switch (self.action) {
            .strong_buy => 1.0,
            .buy => 0.75,
            .hold => 0.5,
            .sell => 0.25,
            .strong_sell => 0.0,
        };
    }
};
```

### MarketContext

```zig
pub const MarketContext = struct {
    pair: TradingPair,
    current_price: Decimal,
    price_change_24h: f64,
    indicators: []const IndicatorSnapshot,
    recent_candles: []const Candle,
    position: ?Position,
};
```

### IndicatorSnapshot

```zig
pub const IndicatorSnapshot = struct {
    name: []const u8,
    value: f64,
    interpretation: []const u8,  // "oversold", "bullish", etc.
};
```

---

## 配置参考

### AIConfig 参数说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `provider` | `AIProvider` | - | AI 提供商 |
| `model_id` | `[]const u8` | - | 模型标识 |
| `api_key` | `[]const u8` | - | API 密钥 |
| `max_tokens` | `u32` | 1024 | 最大生成 token 数 |
| `temperature` | `f32` | 0.3 | 生成温度 (0-1) |
| `timeout_ms` | `u32` | 30000 | 请求超时 (毫秒) |

### HybridAIStrategy 配置

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `ai_weight` | `f64` | 0.4 | AI 建议权重 |
| `technical_weight` | `f64` | 0.6 | 技术指标权重 |
| `min_combined_score` | `f64` | 0.6 | 最小综合得分阈值 |
| `rsi_period` | `u32` | 14 | RSI 周期 |
| `rsi_oversold` | `f64` | 30 | RSI 超卖阈值 |
| `rsi_overbought` | `f64` | 70 | RSI 超买阈值 |
| `sma_period` | `u32` | 20 | SMA 周期 |

---

## 错误处理

### 常见错误

| 错误 | 说明 | 处理建议 |
|------|------|----------|
| `error.UnsupportedProvider` | 不支持的 AI 提供商 | 检查 provider 配置 |
| `error.InvalidWeights` | 权重配置无效 | 确保权重之和为 1.0 |
| `error.Timeout` | API 请求超时 | 增加 timeout_ms |
| `error.ApiError` | API 返回错误 | 检查 API 密钥和配额 |

### 容错机制

HybridAIStrategy 在 AI 调用失败时会自动回退到纯技术指标决策：

```zig
const ai_advice = self.ai_advisor.getAdvice(market_ctx) catch |err| {
    self.logger.warn("AI advice failed: {}, falling back to technical only", .{err});
    // 使用纯技术指标生成信号
    return generateSignalFromTechnical(self, technical_action, technical_score, candles, index);
};
```

---

## 性能考虑

### 延迟

| 场景 | 预期延迟 |
|------|----------|
| AI API 调用 | 500ms - 5s |
| 技术指标计算 | < 1ms |
| Prompt 构建 | < 1ms |

### 成本优化

- 设置合理的 `max_tokens` (默认 1024)
- 使用较低成本的模型 (如 claude-haiku)
- 减少高频场景下的 AI 调用频率
- 实现响应缓存 (配置 `cache_ttl_seconds`)

### 模型成本参考

| 模型 | 输入价格 | 输出价格 |
|------|----------|----------|
| OpenAI GPT-4o | ~$5/1M tokens | ~$15/1M tokens |
| Anthropic Claude Sonnet | ~$3/1M tokens | ~$15/1M tokens |
| Anthropic Claude Haiku | ~$0.25/1M tokens | ~$1.25/1M tokens |

---

## 最佳实践

### 1. 权重配置建议

```zig
// 保守配置 - 更依赖技术指标
.ai_weight = 0.3,
.technical_weight = 0.7,

// 平衡配置
.ai_weight = 0.4,
.technical_weight = 0.6,

// 激进配置 - 更依赖 AI
.ai_weight = 0.5,
.technical_weight = 0.5,
```

### 2. 模型选择

- **高频交易**: 使用 claude-haiku (低延迟、低成本)
- **日线策略**: 使用 claude-sonnet-4-5 (平衡性能)
- **重要决策**: 使用 claude-opus-4-5 或 gpt-4 (最佳推理)

### 3. Prompt 优化

使用 `PromptBuilder` 构建结构化的市场分析 Prompt，包含：
- 当前市场数据
- 技术指标解读
- 仓位上下文
- 明确的任务描述

---

## 相关文档

- [Story 046: AI 策略集成](../../stories/v0.9.0/STORY_046_AI_STRATEGY.md)
- [v0.9.0 版本概览](../../stories/v0.9.0/OVERVIEW.md)
- [实现细节](./implementation.md)
- [Release Notes](../../releases/RELEASE_v0.9.0.md)

---

*最后更新: 2025-12-28*
