# AI 模块实现细节

**版本**: v0.9.0
**最后更新**: 2025-12-28

---

## 架构概述

AI 模块采用分层架构设计，确保关注点分离和可测试性：

```
┌─────────────────────────────────────────────────────────────┐
│                    HybridAIStrategy                         │
│              (混合策略 - 实现 IStrategy)                     │
├─────────────────────────────────────────────────────────────┤
│                       AIAdvisor                             │
│              (AI 建议服务 - 业务逻辑)                        │
├─────────────────────────────────────────────────────────────┤
│     PromptBuilder    │           ILLMClient                 │
│    (Prompt 构建)     │      (LLM 客户端接口)                │
├──────────────────────┴──────────────────────────────────────┤
│                        LLMClient                            │
│           (具体实现 - OpenAI/Anthropic)                     │
├─────────────────────────────────────────────────────────────┤
│                       zig-ai-sdk                            │
│              (底层 AI 库 - 30+ 提供商)                       │
└─────────────────────────────────────────────────────────────┘
```

---

## VTable 模式

### 设计理念

与项目现有架构保持一致，AI 模块使用 VTable 模式实现接口多态。这种模式在 Zig 中是实现运行时多态的标准方式。

### ILLMClient 接口

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

    // 便捷方法代理到 vtable
    pub fn generateText(self: ILLMClient, prompt: []const u8) ![]const u8 {
        return self.vtable.generateText(self.ptr, prompt);
    }
    // ... 其他方法
};
```

### 实现模式

```zig
pub const LLMClient = struct {
    allocator: std.mem.Allocator,
    config: AIConfig,
    // ... 其他字段

    pub fn toInterface(self: *LLMClient) ILLMClient {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    // VTable 实现函数
    fn generateTextImpl(ptr: *anyopaque, prompt: []const u8) anyerror![]const u8 {
        const self: *LLMClient = @ptrCast(@alignCast(ptr));
        // 实际实现...
    }

    const vtable = ILLMClient.VTable{
        .generateText = generateTextImpl,
        .generateObject = generateObjectImpl,
        .getModel = getModelImpl,
        .isConnected = isConnectedImpl,
        .deinit = deinitImpl,
    };
};
```

### Mock 实现 (测试用)

```zig
pub const MockLLMClient = struct {
    response: []const u8,
    call_count: u32 = 0,

    pub fn init(response: []const u8) MockLLMClient {
        return .{ .response = response };
    }

    pub fn toInterface(self: *MockLLMClient) ILLMClient {
        return .{
            .ptr = self,
            .vtable = &mock_vtable,
        };
    }

    fn generateTextImpl(ptr: *anyopaque, _: []const u8) anyerror![]const u8 {
        const self: *MockLLMClient = @ptrCast(@alignCast(ptr));
        self.call_count += 1;
        return self.response;
    }

    const mock_vtable = ILLMClient.VTable{
        .generateText = generateTextImpl,
        // ... 其他 mock 实现
    };
};
```

---

## openai-zig 集成

### 依赖配置

```zig
// build.zig.zon
.openai_zig = .{
    .url = "https://github.com/DaviRain-Su/openai-zig/archive/refs/heads/master.tar.gz",
    .hash = "openai_zig-0.0.0-xCfcQBnxBQDkrxZmwJkZsZgZP6KOpZU7qqlOqjfpseHO",
},
```

> **注意**: 原计划使用 `zig-ai-sdk`，但由于与 Zig 0.15 的兼容性问题，改用 `openai-zig` 库。

### build.zig 配置

```zig
// 添加 openai-zig 模块
const openai_zig = b.dependency("openai_zig", .{
    .target = target,
    .optimize = optimize,
});

// 添加到库模块
.{ .name = "openai_zig", .module = openai_zig.module("openai_zig") },
```

### 核心 API 使用

```zig
const openai_zig = @import("openai_zig");

// 创建 OpenAI 客户端
var client = try openai_zig.initClient(allocator, .{
    .api_key = "your-api-key",
    .base_url = "http://127.0.0.1:1234/v1",  // 本地服务
});
defer client.deinit();

// 调用 Chat Completion API
const messages = [_]openai_zig.resources.chat.ChatMessage{
    .{ .role = "user", .content = "Analyze the market..." },
};

const response = try client.chat().create_chat_completion(allocator, .{
    .model = "gpt-4o",
    .messages = &messages,
});
defer response.deinit();
```

### 自定义 JSON 序列化

由于 openai-zig 默认序列化会包含 null 可选字段，我们使用 `rawTransport()` 手动构建 JSON：

```zig
fn callOpenAIChat(self: *LLMClient, allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    var client = self.openai_client.?;

    // 手动构建 JSON 避免 null 字段
    const payload = try self.buildChatRequestJson(allocator, prompt);
    defer allocator.free(payload);

    // 使用 raw transport 发送请求
    const transport = client.rawTransport();
    const resp = try transport.request(.POST, "/chat/completions", &.{
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "Content-Type", .value = "application/json" },
    }, payload);
    defer transport.allocator.free(resp.body);

    // 解析响应...
}
```

### Markdown 代码块处理

AI 可能返回 markdown 包装的 JSON，使用 `extractJsonContent` 函数处理：

```zig
/// 从 markdown 代码块中提取 JSON
fn extractJsonContent(response: []const u8) []const u8 {
    var content = std.mem.trim(u8, response, " \t\n\r");

    // 检查 markdown 代码块
    if (std.mem.startsWith(u8, content, "```")) {
        // 跳过 ```json 或 ```
        if (std.mem.indexOf(u8, content, "\n")) |first_newline| {
            content = content[first_newline + 1 ..];
        }

        // 移除结尾的 ```
        if (std.mem.lastIndexOf(u8, content, "```")) |closing| {
            content = content[0..closing];
        }
        content = std.mem.trim(u8, content, " \t\n\r");
    }

    // 提取 JSON 对象
    const start = std.mem.indexOf(u8, content, "{") orelse return content;
    const end = std.mem.lastIndexOf(u8, content, "}") orelse return content;

    if (end >= start) {
        return content[start .. end + 1];
    }
    return content;
}
```

---

## Prompt 工程

### 设计原则

1. **结构化** - 使用清晰的章节组织信息
2. **专业性** - 使用交易领域术语
3. **约束性** - 明确输出格式要求
4. **上下文** - 提供完整的市场上下文

### Prompt 模板

```zig
pub fn buildMarketAnalysisPrompt(self: *PromptBuilder, ctx: MarketContext) ![]const u8 {
    self.buffer.clearRetainingCapacity();
    const writer = self.buffer.writer();

    try writer.writeAll(
        \\You are a professional quantitative trading analyst. Analyze the following market data and provide a trading recommendation.
        \\
        \\## Market Data
        \\
    );

    try writer.print("- Trading Pair: {s}/{s}\n", .{ctx.pair.base, ctx.pair.quote});
    try writer.print("- Current Price: {d:.4}\n", .{ctx.current_price.toFloat()});
    try writer.print("- 24h Change: {d:+.2}%\n", .{ctx.price_change_24h * 100});

    try writer.writeAll("\n## Technical Indicators\n\n");
    for (ctx.indicators) |ind| {
        try writer.print("- {s}: {d:.4} ({s})\n", .{ind.name, ind.value, ind.interpretation});
    }

    if (ctx.position) |pos| {
        try writer.writeAll("\n## Current Position\n\n");
        try writer.print("- Side: {s}\n", .{@tagName(pos.side)});
        try writer.print("- Entry Price: {d:.4}\n", .{pos.entry_price.toFloat()});
        try writer.print("- Unrealized PnL: {d:+.2}%\n", .{pos.unrealized_pnl_pct});
    }

    try writer.writeAll(
        \\
        \\## Task
        \\Based on the above data, provide your trading recommendation.
        \\Consider:
        \\1. Current market trend
        \\2. Technical indicator signals
        \\3. Risk management
        \\4. Position sizing
        \\
        \\Respond with a structured recommendation including action, confidence level, and reasoning.
        \\
    );

    return self.buffer.items;
}
```

### JSON Schema 约束

```zig
pub fn getAdviceSchema() []const u8 {
    return
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "action": {
        \\      "type": "string",
        \\      "enum": ["strong_buy", "buy", "hold", "sell", "strong_sell"],
        \\      "description": "Trading action recommendation"
        \\    },
        \\    "confidence": {
        \\      "type": "number",
        \\      "minimum": 0,
        \\      "maximum": 1,
        \\      "description": "Confidence level from 0 to 1"
        \\    },
        \\    "reasoning": {
        \\      "type": "string",
        \\      "description": "Detailed explanation for the recommendation"
        \\    }
        \\  },
        \\  "required": ["action", "confidence", "reasoning"],
        \\  "additionalProperties": false
        \\}
    ;
}
```

---

## 错误处理

### 错误类型

```zig
pub const AIError = error{
    UnsupportedProvider,
    InvalidWeights,
    InvalidConfig,
    Timeout,
    ApiError,
    ParseError,
    RateLimited,
    ConnectionFailed,
};
```

### 重试机制

```zig
pub fn getAdviceWithRetry(self: *AIAdvisor, ctx: MarketContext) !AIAdvice {
    var last_error: anyerror = error.Unknown;

    for (0..self.config.max_retries + 1) |attempt| {
        const advice = self.getAdvice(ctx) catch |err| {
            last_error = err;
            self.logger.warn("AI request failed (attempt {}/{}): {}", .{
                attempt + 1,
                self.config.max_retries + 1,
                err,
            });

            // 指数退避
            if (attempt < self.config.max_retries) {
                const delay = std.math.pow(u64, 2, attempt) * 1000;
                std.time.sleep(delay * std.time.ns_per_ms);
            }
            continue;
        };
        return advice;
    }

    return last_error;
}
```

### 容错回退

```zig
fn generateEntrySignalImpl(ptr: *anyopaque, candles: *Candles, index: usize) ?Signal {
    const self: *HybridAIStrategy = @ptrCast(@alignCast(ptr));

    // 技术分析 (始终执行)
    const technical_result = self.analyzeTechnical(candles, index);

    // AI 分析 (可能失败)
    const ai_advice = self.ai_advisor.getAdvice(market_ctx) catch |err| {
        self.logger.warn("AI advice failed: {}, using technical only", .{err});

        // 回退到纯技术指标
        return self.generateSignalFromTechnical(technical_result, candles, index);
    };

    // 混合决策
    return self.combineSignals(technical_result, ai_advice, candles, index);
}
```

---

## 性能优化

### 响应缓存

```zig
pub const CachedAdvisor = struct {
    advisor: *AIAdvisor,
    cache: std.StringHashMap(CacheEntry),
    ttl_seconds: u32,

    const CacheEntry = struct {
        advice: AIAdvice,
        timestamp: i64,
    };

    pub fn getAdvice(self: *CachedAdvisor, ctx: MarketContext) !AIAdvice {
        const key = self.buildCacheKey(ctx);

        // 检查缓存
        if (self.cache.get(key)) |entry| {
            const age = std.time.timestamp() - entry.timestamp;
            if (age < self.ttl_seconds) {
                return entry.advice;
            }
        }

        // 调用 AI
        const advice = try self.advisor.getAdvice(ctx);

        // 更新缓存
        try self.cache.put(key, .{
            .advice = advice,
            .timestamp = std.time.timestamp(),
        });

        return advice;
    }
};
```

### 延迟追踪

```zig
pub fn getAdvice(self: *AIAdvisor, ctx: MarketContext) !AIAdvice {
    const start = std.time.milliTimestamp();
    defer {
        const latency = std.time.milliTimestamp() - start;
        self.updateLatencyStats(@intCast(latency));
    }

    // ... AI 调用逻辑
}

fn updateLatencyStats(self: *AIAdvisor, latency: u64) void {
    const n = self.successful_requests;
    const old_avg = self.avg_latency_ms;

    // 增量平均计算
    self.avg_latency_ms = old_avg + (@as(f64, @floatFromInt(latency)) - old_avg) / @as(f64, @floatFromInt(n + 1));
}
```

### Token 优化

```zig
pub const TokenOptimizer = struct {
    max_context_candles: u32 = 10,
    max_indicators: u32 = 5,
    truncate_reasoning: bool = true,
    max_reasoning_length: u32 = 200,

    pub fn optimizeContext(self: *TokenOptimizer, ctx: MarketContext) MarketContext {
        var optimized = ctx;

        // 限制 K 线数量
        if (ctx.recent_candles.len > self.max_context_candles) {
            optimized.recent_candles = ctx.recent_candles[ctx.recent_candles.len - self.max_context_candles ..];
        }

        // 限制指标数量
        if (ctx.indicators.len > self.max_indicators) {
            optimized.indicators = ctx.indicators[0..self.max_indicators];
        }

        return optimized;
    }
};
```

---

## 测试策略

### 单元测试

```zig
test "AIAdvice.toScore" {
    const advice = AIAdvice{
        .action = .buy,
        .confidence = 0.8,
        .reasoning = "Bullish signal",
        .timestamp = 0,
    };
    try std.testing.expectEqual(@as(f64, 0.75), advice.toScore());
}

test "PromptBuilder.buildMarketAnalysisPrompt" {
    var builder = PromptBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const ctx = MarketContext{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = Decimal.fromFloat(45000.0),
        .price_change_24h = 0.025,
        .indicators = &.{
            .{ .name = "RSI", .value = 35.5, .interpretation = "approaching oversold" },
        },
        .recent_candles = &.{},
        .position = null,
    };

    const prompt = try builder.buildMarketAnalysisPrompt(ctx);

    try std.testing.expect(std.mem.indexOf(u8, prompt, "BTC/USDT") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "45000") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "RSI") != null);
}
```

### Mock 测试

```zig
test "AIAdvisor with mock LLM" {
    var mock = MockLLMClient.init(
        \\{"action": "buy", "confidence": 0.85, "reasoning": "Strong bullish momentum"}
    );

    var advisor = AIAdvisor.init(
        std.testing.allocator,
        mock.toInterface(),
        .{},
    );
    defer advisor.deinit();

    const ctx = createTestContext();
    const advice = try advisor.getAdvice(ctx);

    try std.testing.expectEqual(AIAdvice.Action.buy, advice.action);
    try std.testing.expectEqual(@as(f64, 0.85), advice.confidence);
    try std.testing.expectEqual(@as(u32, 1), mock.call_count);
}
```

### 集成测试

```zig
test "HybridAIStrategy signal generation" {
    // 使用 Mock LLM 避免实际 API 调用
    var strategy = try createTestHybridStrategy(std.testing.allocator);
    defer strategy.destroy();

    const candles = try loadTestCandles(std.testing.allocator);
    defer candles.deinit();

    // 测试信号生成
    const signal = strategy.toStrategy().generateEntrySignal(&candles, 50);

    if (signal) |s| {
        try std.testing.expect(s.strength >= 0.0 and s.strength <= 1.0);
    }
}
```

### 内存泄漏检测

```zig
test "no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) @panic("Memory leak detected!");
    }
    const allocator = gpa.allocator();

    var client = try LLMClient.init(allocator, test_config);
    client.deinit();

    var advisor = AIAdvisor.init(allocator, client.toInterface(), .{});
    advisor.deinit();
}
```

---

## 文件结构

```
src/ai/
├── mod.zig              # 模块导出入口
├── types.zig            # 类型定义
│   ├── AIProvider       # AI 提供商枚举
│   ├── AIModel          # AI 模型信息
│   ├── AIAdvice         # 交易建议
│   ├── AIConfig         # 配置
│   └── MarketContext    # 市场上下文
├── interfaces.zig       # 接口定义
│   └── ILLMClient       # LLM 客户端接口
├── client.zig           # 客户端实现
│   └── LLMClient        # 多提供商客户端
├── advisor.zig          # AI Advisor
│   └── AIAdvisor        # 交易建议服务
└── prompt_builder.zig   # Prompt 构建
    └── PromptBuilder    # Prompt 构建器

src/strategy/builtin/
└── hybrid_ai.zig        # 混合策略
    └── HybridAIStrategy # 技术+AI 混合策略
```

---

## 扩展指南

### 添加新的 AI 提供商

1. 在 `AIProvider` 枚举中添加新值：

```zig
pub const AIProvider = enum {
    openai,
    anthropic,
    google,
    ollama,    // 新增
    custom,
};
```

2. 在 `LLMClient` 中添加提供商处理：

```zig
const ProviderUnion = union(AIProvider) {
    openai: openai.OpenAI,
    anthropic: anthropic.Anthropic,
    google: google.Google,
    ollama: OllamaClient,  // 新增
    custom: void,
};

pub fn init(allocator: std.mem.Allocator, config: AIConfig) !*LLMClient {
    // ...
    self.provider = switch (config.provider) {
        .openai => .{ .openai = openai.createOpenAI(allocator) },
        .anthropic => .{ .anthropic = anthropic.createAnthropic(allocator) },
        .ollama => .{ .ollama = try OllamaClient.init(allocator) },
        else => return error.UnsupportedProvider,
    };
}
```

### 自定义 Prompt 策略

实现 `IPromptBuilder` 接口：

```zig
pub const IPromptBuilder = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        build: *const fn (ptr: *anyopaque, ctx: MarketContext) anyerror![]const u8,
        getSchema: *const fn (ptr: *anyopaque) []const u8,
    };
};
```

---

## 相关文档

- [AI 模块 API](./README.md)
- [Story 046: AI 策略集成](../../stories/v0.9.0/STORY_046_AI_STRATEGY.md)
- [v0.9.0 版本概览](../../stories/v0.9.0/OVERVIEW.md)

---

*最后更新: 2025-12-28*
