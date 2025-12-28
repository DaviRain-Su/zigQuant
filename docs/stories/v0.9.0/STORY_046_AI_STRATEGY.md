# Story 046: AI 策略集成

**版本**: v0.9.0
**优先级**: P1
**状态**: 开发中
**预估工作量**: 3-4 天

---

## 概述

基于 `zig-ai-sdk` 实现 AI 辅助交易决策系统，包含 LLM 抽象层、AI Advisor 辅助决策服务和 HybridAIStrategy 混合策略。

### 目标

1. 提供统一的 LLM 客户端接口（ILLMClient）
2. 实现 OpenAI 和 Anthropic 客户端
3. 创建 AIAdvisor 提供结构化交易建议
4. 实现 HybridAIStrategy 混合决策策略
5. 完整的测试和文档

---

## 背景

### 动机

- 传统技术指标在某些市场条件下表现有限
- LLM 可以综合分析多维度市场信息
- 混合决策可以结合两者优势

### 依赖

```zig
.@"zig-ai-sdk" = .{
    .url = "https://github.com/evmts/ai-zig/archive/refs/heads/master.tar.gz",
    .hash = "zig_ai_sdk-0.1.0-ULWwFOjsNQDpPPJBPUBUJKikJkiIAASwHYLwqyzEmcim",
},
```

### 现有架构参考

- **VTable 模式**: 参考 `IStrategy`, `IExchange` 接口设计
- **策略模式**: 参考 `DualMAStrategy`, `RSIMeanReversionStrategy`
- **模块组织**: 参考 `src/strategy/`, `src/exchange/`

---

## 技术规格

### 1. 类型定义 (`src/ai/types.zig`)

```zig
/// AI 提供商枚举
pub const AIProvider = enum {
    openai,
    anthropic,
    google,
    custom,
};

/// AI 模型信息
pub const AIModel = struct {
    provider: AIProvider,
    model_id: []const u8,  // "gpt-4o", "claude-sonnet-4-5"
};

/// AI 交易建议
pub const AIAdvice = struct {
    action: Action,
    confidence: f64,        // [0.0, 1.0]
    reasoning: []const u8,  // AI 解释
    timestamp: i64,

    pub const Action = enum {
        strong_buy,   // 强烈买入信号
        buy,          // 买入信号
        hold,         // 持有/观望
        sell,         // 卖出信号
        strong_sell,  // 强烈卖出信号
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

/// 市场上下文 (用于 Prompt 构建)
pub const MarketContext = struct {
    pair: TradingPair,
    current_price: Decimal,
    price_change_24h: f64,
    indicators: []const IndicatorSnapshot,
    recent_candles: []const Candle,
    position: ?Position,
};

/// 指标快照
pub const IndicatorSnapshot = struct {
    name: []const u8,
    value: f64,
    interpretation: []const u8,  // "oversold", "bullish", etc.
};

/// AI 配置
pub const AIConfig = struct {
    provider: AIProvider,
    model_id: []const u8,
    api_key: []const u8,
    max_tokens: u32 = 1024,
    temperature: f32 = 0.3,    // 低温度更确定性
    timeout_ms: u32 = 30000,
};
```

### 2. ILLMClient 接口 (`src/ai/interfaces.zig`)

```zig
/// LLM 客户端接口 (VTable 模式)
pub const ILLMClient = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// 生成文本响应
        generateText: *const fn (
            ptr: *anyopaque,
            prompt: []const u8,
        ) anyerror![]const u8,

        /// 生成结构化响应 (JSON)
        generateObject: *const fn (
            ptr: *anyopaque,
            prompt: []const u8,
            schema: []const u8,
        ) anyerror![]const u8,

        /// 获取模型信息
        getModel: *const fn (ptr: *anyopaque) AIModel,

        /// 检查连接状态
        isConnected: *const fn (ptr: *anyopaque) bool,

        /// 释放资源
        deinit: *const fn (ptr: *anyopaque) void,
    };

    // 便捷方法
    pub fn generateText(self: ILLMClient, prompt: []const u8) ![]const u8 {
        return self.vtable.generateText(self.ptr, prompt);
    }

    pub fn generateObject(self: ILLMClient, prompt: []const u8, schema: []const u8) ![]const u8 {
        return self.vtable.generateObject(self.ptr, prompt, schema);
    }

    pub fn getModel(self: ILLMClient) AIModel {
        return self.vtable.getModel(self.ptr);
    }

    pub fn isConnected(self: ILLMClient) bool {
        return self.vtable.isConnected(self.ptr);
    }

    pub fn deinit(self: ILLMClient) void {
        self.vtable.deinit(self.ptr);
    }
};
```

### 3. LLMClient 实现 (`src/ai/client.zig`)

```zig
const ai = @import("ai");
const openai = @import("openai");
const anthropic = @import("anthropic");

pub const LLMClient = struct {
    allocator: std.mem.Allocator,
    config: AIConfig,
    provider: ProviderUnion,
    connected: bool,

    const ProviderUnion = union(AIProvider) {
        openai: openai.OpenAI,
        anthropic: anthropic.Anthropic,
        google: void,
        custom: void,
    };

    pub fn init(allocator: std.mem.Allocator, config: AIConfig) !*LLMClient {
        const self = try allocator.create(LLMClient);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .config = config,
            .provider = switch (config.provider) {
                .openai => .{ .openai = openai.createOpenAI(allocator) },
                .anthropic => .{ .anthropic = anthropic.createAnthropic(allocator) },
                else => return error.UnsupportedProvider,
            },
            .connected = true,
        };

        return self;
    }

    pub fn deinit(self: *LLMClient) void {
        switch (self.provider) {
            .openai => |*p| p.deinit(),
            .anthropic => |*p| p.deinit(),
            else => {},
        }
        self.allocator.destroy(self);
    }

    pub fn toInterface(self: *LLMClient) ILLMClient {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
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

### 4. PromptBuilder (`src/ai/prompt_builder.zig`)

```zig
pub const PromptBuilder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    /// 构建市场分析 Prompt
    pub fn buildMarketAnalysisPrompt(self: *PromptBuilder, ctx: MarketContext) ![]const u8 {
        // 格式化市场数据、技术指标、仓位信息
        // 返回专业的交易分析 prompt
    }

    /// AIAdvice 的 JSON Schema
    pub fn getAdviceSchema() []const u8 {
        return
            \\{
            \\  "type": "object",
            \\  "properties": {
            \\    "action": {
            \\      "type": "string",
            \\      "enum": ["strong_buy", "buy", "hold", "sell", "strong_sell"]
            \\    },
            \\    "confidence": {
            \\      "type": "number",
            \\      "minimum": 0,
            \\      "maximum": 1
            \\    },
            \\    "reasoning": {
            \\      "type": "string"
            \\    }
            \\  },
            \\  "required": ["action", "confidence", "reasoning"]
            \\}
        ;
    }
};
```

### 5. AIAdvisor (`src/ai/advisor.zig`)

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

    /// 获取 AI 交易建议
    pub fn getAdvice(self: *AIAdvisor, ctx: MarketContext) !AIAdvice {
        // 1. 构建 prompt
        // 2. 调用 LLM (generateObject)
        // 3. 解析 JSON 响应
        // 4. 更新统计
        // 5. 返回 AIAdvice
    }

    /// 获取统计信息
    pub fn getStats(self: *AIAdvisor) AdvisorStats {
        return .{
            .total_requests = self.total_requests,
            .successful_requests = self.successful_requests,
            .success_rate = ...,
            .avg_latency_ms = self.avg_latency_ms,
        };
    }
};
```

### 6. HybridAIStrategy (`src/strategy/builtin/hybrid_ai.zig`)

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
        ai_weight: f64 = 0.4,        // AI 建议权重 [0, 1]
        technical_weight: f64 = 0.6,  // 技术指标权重

        // 信号阈值
        min_combined_score: f64 = 0.6,

        // AI 配置
        ai_config: AIConfig,
    };

    // 实现 IStrategy VTable
    const vtable = IStrategy.VTable{
        .init = initImpl,
        .deinit = deinitImpl,
        .populateIndicators = populateIndicatorsImpl,
        .generateEntrySignal = generateEntrySignalImpl,
        .generateExitSignal = generateExitSignalImpl,
        .calculatePositionSize = calculatePositionSizeImpl,
        .getParameters = getParametersImpl,
        .getMetadata = getMetadataImpl,
    };
};
```

---

## 验收标准

### 功能验收

- [ ] ILLMClient 接口定义完整
- [ ] LLMClient 支持 OpenAI 和 Anthropic
- [ ] AIAdvisor 返回结构化 AIAdvice
- [ ] HybridAIStrategy 实现 IStrategy 接口
- [ ] 权重配置生效
- [ ] AI 失败时回退到纯技术指标

### 测试验收

- [ ] 类型定义单元测试
- [ ] ILLMClient 接口测试 (Mock)
- [ ] PromptBuilder 测试
- [ ] AIAdvisor 测试 (Mock LLM)
- [ ] HybridAIStrategy 集成测试
- [ ] 零内存泄漏

### 性能验收

- [ ] AI 请求超时处理 (默认 30s)
- [ ] 请求统计准确
- [ ] 延迟追踪正常

### 文档验收

- [ ] API 文档完整
- [ ] 使用示例正确
- [ ] 配置说明清晰

---

## 实现步骤

### Phase 1: 基础设施 (Day 1)

1. 创建 `src/ai/` 目录结构
2. 实现 `types.zig` 类型定义
3. 实现 `interfaces.zig` ILLMClient 接口
4. 更新 `build.zig` 添加依赖

### Phase 2: LLM 客户端 (Day 2)

1. 实现 `client.zig` LLMClient
2. 实现 `prompt_builder.zig`
3. 添加单元测试

### Phase 3: AIAdvisor (Day 3)

1. 实现 `advisor.zig`
2. 创建 `mod.zig` 模块导出
3. 更新 `root.zig` 导出
4. 添加集成测试

### Phase 4: 混合策略 (Day 4)

1. 实现 `hybrid_ai.zig`
2. 创建示例代码
3. 完善文档
4. 全面测试

---

## 风险与缓解

### 风险 1: AI API 延迟

**问题**: LLM API 调用可能需要 1-5 秒
**缓解**:
- 设置超时机制
- 失败时回退到纯技术指标
- 可配置调用频率

### 风险 2: API 成本

**问题**: 频繁调用 AI API 成本较高
**缓解**:
- 设置 `max_tokens` 限制
- 实现响应缓存
- 仅在关键决策点调用

### 风险 3: zig-ai-sdk 兼容性

**问题**: 第三方库可能有兼容性问题
**缓解**:
- 抽象 ILLMClient 接口
- 支持多个提供商
- 可切换到其他实现

---

## 依赖

### 外部依赖

- `zig-ai-sdk` v0.1.0

### 内部依赖

- `src/strategy/interface.zig` - IStrategy 接口
- `src/strategy/types.zig` - Signal, TradingPair 等
- `src/indicators/` - 技术指标

---

## 测试计划

### 单元测试

```zig
test "AIAdvice.toScore" {
    const advice = AIAdvice{ .action = .buy, ... };
    try std.testing.expectEqual(0.75, advice.toScore());
}

test "PromptBuilder.buildMarketAnalysisPrompt" {
    // 测试 prompt 格式化
}

test "LLMClient.init with OpenAI" {
    // 测试客户端初始化
}
```

### 集成测试

```zig
test "AIAdvisor with mock LLM" {
    // 使用 Mock 测试完整流程
}

test "HybridAIStrategy signal generation" {
    // 测试信号生成逻辑
}
```

### Mock 实现

```zig
pub const MockLLMClient = struct {
    response: []const u8,

    pub fn init(response: []const u8) MockLLMClient {
        return .{ .response = response };
    }

    pub fn toInterface(self: *MockLLMClient) ILLMClient {
        return .{
            .ptr = self,
            .vtable = &mock_vtable,
        };
    }
};
```

---

## 相关文档

- [v0.9.0 概览](./OVERVIEW.md)
- [AI 模块 API](../../features/ai/README.md)
- [实现细节](../../features/ai/implementation.md)

---

*最后更新: 2025-12-28*
