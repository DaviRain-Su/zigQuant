# AI 模块 - API 参考

> 完整的 API 文档

**模块路径**: `src/ai/`
**版本**: v0.9.0
**最后更新**: 2025-12-28

---

## 目录

1. [类型定义](#类型定义)
2. [接口](#接口)
3. [客户端](#客户端)
4. [Advisor](#advisor)
5. [Prompt Builder](#prompt-builder)
6. [策略](#策略)
7. [完整示例](#完整示例)

---

## 类型定义

### AIProvider

AI 服务提供商枚举。

```zig
pub const AIProvider = enum {
    openai,     // OpenAI (GPT-4o, o1, o3)
    anthropic,  // Anthropic (Claude Sonnet, Opus, Haiku)
    google,     // Google (Gemini) - 规划中
    custom,     // 自定义提供商
};
```

---

### AIModel

AI 模型信息结构。

```zig
pub const AIModel = struct {
    provider: AIProvider,
    model_id: []const u8,  // 例如: "gpt-4o", "claude-sonnet-4-5"
};
```

**字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `provider` | `AIProvider` | AI 提供商 |
| `model_id` | `[]const u8` | 模型标识符 |

---

### AIConfig

AI 配置结构。

```zig
pub const AIConfig = struct {
    provider: AIProvider,
    model_id: []const u8,
    api_key: []const u8,
    max_tokens: u32 = 1024,
    temperature: f32 = 0.3,
    timeout_ms: u32 = 30000,
};
```

**字段**:
| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `provider` | `AIProvider` | - | AI 提供商 |
| `model_id` | `[]const u8` | - | 模型标识符 |
| `api_key` | `[]const u8` | - | API 密钥 |
| `max_tokens` | `u32` | 1024 | 最大生成 token 数 |
| `temperature` | `f32` | 0.3 | 生成温度 (0-1) |
| `timeout_ms` | `u32` | 30000 | 请求超时 (毫秒) |

---

### AIAdvice

AI 交易建议结构。

```zig
pub const AIAdvice = struct {
    action: Action,
    confidence: f64,
    reasoning: []const u8,
    timestamp: i64,

    pub const Action = enum {
        strong_buy,
        buy,
        hold,
        sell,
        strong_sell,
    };

    /// 将 Action 转换为得分 [0, 1]
    pub fn toScore(self: AIAdvice) f64;
};
```

**字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `action` | `Action` | 交易动作建议 |
| `confidence` | `f64` | 置信度 [0.0, 1.0] |
| `reasoning` | `[]const u8` | AI 解释说明 |
| `timestamp` | `i64` | 建议生成时间戳 |

**Action 得分映射**:
| Action | Score |
|--------|-------|
| `strong_buy` | 1.0 |
| `buy` | 0.75 |
| `hold` | 0.5 |
| `sell` | 0.25 |
| `strong_sell` | 0.0 |

---

### MarketContext

市场上下文结构，用于构建 Prompt。

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

**字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `pair` | `TradingPair` | 交易对 |
| `current_price` | `Decimal` | 当前价格 |
| `price_change_24h` | `f64` | 24 小时价格变化 |
| `indicators` | `[]const IndicatorSnapshot` | 技术指标快照 |
| `recent_candles` | `[]const Candle` | 最近 K 线数据 |
| `position` | `?Position` | 当前仓位 (可选) |

---

### IndicatorSnapshot

指标快照结构。

```zig
pub const IndicatorSnapshot = struct {
    name: []const u8,
    value: f64,
    interpretation: []const u8,
};
```

**字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `[]const u8` | 指标名称 (如 "RSI") |
| `value` | `f64` | 指标数值 |
| `interpretation` | `[]const u8` | 指标解读 (如 "oversold") |

---

## 接口

### ILLMClient

LLM 客户端接口 (VTable 模式)。

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

    // 便捷方法
    pub fn generateText(self: ILLMClient, prompt: []const u8) ![]const u8;
    pub fn generateObject(self: ILLMClient, prompt: []const u8, schema: []const u8) ![]const u8;
    pub fn getModel(self: ILLMClient) AIModel;
    pub fn isConnected(self: ILLMClient) bool;
    pub fn deinit(self: ILLMClient) void;
};
```

#### `generateText`

```zig
pub fn generateText(self: ILLMClient, prompt: []const u8) ![]const u8
```

**描述**: 生成文本响应。

**参数**:
- `prompt`: 输入提示词

**返回**: 生成的文本响应

**错误**:
- `error.Timeout`: 请求超时
- `error.ApiError`: API 返回错误

**示例**:
```zig
const response = try client.generateText("Analyze BTC market conditions");
defer allocator.free(response);
std.debug.print("Response: {s}\n", .{response});
```

---

#### `generateObject`

```zig
pub fn generateObject(self: ILLMClient, prompt: []const u8, schema: []const u8) ![]const u8
```

**描述**: 生成结构化 JSON 响应。

**参数**:
- `prompt`: 输入提示词
- `schema`: JSON Schema 约束

**返回**: 符合 schema 的 JSON 字符串

**错误**:
- `error.Timeout`: 请求超时
- `error.ApiError`: API 返回错误
- `error.ParseError`: 响应解析失败

**示例**:
```zig
const schema = PromptBuilder.getAdviceSchema();
const json = try client.generateObject("Give trading advice for BTC", schema);
defer allocator.free(json);
```

---

#### `getModel`

```zig
pub fn getModel(self: ILLMClient) AIModel
```

**描述**: 获取当前模型信息。

**返回**: `AIModel` 结构

---

#### `isConnected`

```zig
pub fn isConnected(self: ILLMClient) bool
```

**描述**: 检查客户端连接状态。

**返回**: `true` 如果已连接

---

## 客户端

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

#### `init`

```zig
pub fn init(allocator: std.mem.Allocator, config: AIConfig) !*LLMClient
```

**描述**: 创建 LLM 客户端实例。

**参数**:
- `allocator`: 内存分配器
- `config`: AI 配置

**返回**: 客户端指针

**错误**:
- `error.UnsupportedProvider`: 不支持的提供商
- `error.OutOfMemory`: 内存不足

**示例**:
```zig
const client = try LLMClient.init(allocator, .{
    .provider = .anthropic,
    .model_id = "claude-sonnet-4-5",
    .api_key = api_key,
    .temperature = 0.3,
});
defer client.deinit();
```

---

#### `deinit`

```zig
pub fn deinit(self: *LLMClient) void
```

**描述**: 释放客户端资源。

---

#### `toInterface`

```zig
pub fn toInterface(self: *LLMClient) ILLMClient
```

**描述**: 转换为 `ILLMClient` 接口。

**返回**: `ILLMClient` 接口实例

---

## Advisor

### AIAdvisor

AI 交易建议服务。

```zig
pub const AIAdvisor = struct {
    allocator: std.mem.Allocator,
    client: ILLMClient,
    prompt_builder: PromptBuilder,
    config: AdvisorConfig,
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

#### `init`

```zig
pub fn init(allocator: std.mem.Allocator, client: ILLMClient, config: AdvisorConfig) AIAdvisor
```

**描述**: 创建 AIAdvisor 实例。

**参数**:
- `allocator`: 内存分配器
- `client`: LLM 客户端接口
- `config`: Advisor 配置

**返回**: AIAdvisor 实例

---

#### `getAdvice`

```zig
pub fn getAdvice(self: *AIAdvisor, ctx: MarketContext) !AIAdvice
```

**描述**: 获取 AI 交易建议。

**参数**:
- `ctx`: 市场上下文

**返回**: `AIAdvice` 结构

**错误**:
- `error.Timeout`: 请求超时
- `error.ApiError`: API 错误
- `error.ParseError`: 响应解析失败

**示例**:
```zig
const advice = try advisor.getAdvice(.{
    .pair = .{ .base = "BTC", .quote = "USDT" },
    .current_price = Decimal.fromFloat(45000.0),
    .price_change_24h = 0.025,
    .indicators = &.{
        .{ .name = "RSI", .value = 35.5, .interpretation = "oversold" },
    },
    .recent_candles = candles,
    .position = null,
});

std.debug.print("Action: {s}, Confidence: {d:.0}%\n", .{
    @tagName(advice.action),
    advice.confidence * 100,
});
```

---

#### `getStats`

```zig
pub fn getStats(self: *AIAdvisor) AdvisorStats
```

**描述**: 获取 Advisor 统计信息。

**返回**: `AdvisorStats` 结构

```zig
pub const AdvisorStats = struct {
    total_requests: u64,
    successful_requests: u64,
    success_rate: f64,
    avg_latency_ms: f64,
};
```

---

## Prompt Builder

### PromptBuilder

市场分析 Prompt 构建器。

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

#### `buildMarketAnalysisPrompt`

```zig
pub fn buildMarketAnalysisPrompt(self: *PromptBuilder, ctx: MarketContext) ![]const u8
```

**描述**: 构建专业的市场分析 Prompt。

**参数**:
- `ctx`: 市场上下文

**返回**: 格式化的 Prompt 字符串

**示例**:
```zig
var builder = PromptBuilder.init(allocator);
defer builder.deinit();

const prompt = try builder.buildMarketAnalysisPrompt(.{
    .pair = .{ .base = "BTC", .quote = "USDT" },
    .current_price = Decimal.fromFloat(45000.0),
    .price_change_24h = 0.025,
    .indicators = indicators,
    .recent_candles = candles,
    .position = null,
});
```

---

#### `getAdviceSchema`

```zig
pub fn getAdviceSchema() []const u8
```

**描述**: 获取 AIAdvice 的 JSON Schema。

**返回**: JSON Schema 字符串

**示例**:
```zig
const schema = PromptBuilder.getAdviceSchema();
// 用于 generateObject 调用
const response = try client.generateObject(prompt, schema);
```

**Schema 内容**:
```json
{
  "type": "object",
  "properties": {
    "action": {
      "type": "string",
      "enum": ["strong_buy", "buy", "hold", "sell", "strong_sell"]
    },
    "confidence": {
      "type": "number",
      "minimum": 0,
      "maximum": 1
    },
    "reasoning": {
      "type": "string"
    }
  },
  "required": ["action", "confidence", "reasoning"]
}
```

---

## 策略

### HybridAIStrategy

混合 AI 策略，结合技术指标和 AI 建议。

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
        rsi_period: u32 = 14,
        rsi_oversold: f64 = 30,
        rsi_overbought: f64 = 70,
        sma_period: u32 = 20,
        ai_weight: f64 = 0.4,
        technical_weight: f64 = 0.6,
        min_combined_score: f64 = 0.6,
        ai_config: AIConfig,
    };

    pub fn create(allocator: std.mem.Allocator, config: Config) !*HybridAIStrategy;
    pub fn destroy(self: *HybridAIStrategy) void;
    pub fn toStrategy(self: *HybridAIStrategy) IStrategy;
};
```

#### `create`

```zig
pub fn create(allocator: std.mem.Allocator, config: Config) !*HybridAIStrategy
```

**描述**: 创建混合策略实例。

**参数**:
- `allocator`: 内存分配器
- `config`: 策略配置

**返回**: 策略指针

**错误**:
- `error.InvalidWeights`: 权重配置无效 (ai_weight + technical_weight != 1.0)
- `error.UnsupportedProvider`: 不支持的 AI 提供商

**示例**:
```zig
const strategy = try HybridAIStrategy.create(allocator, .{
    .pair = .{ .base = "BTC", .quote = "USDT" },
    .timeframe = .h1,
    .ai_weight = 0.4,
    .technical_weight = 0.6,
    .ai_config = .{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
        .api_key = api_key,
    },
});
defer strategy.destroy();
```

---

#### `toStrategy`

```zig
pub fn toStrategy(self: *HybridAIStrategy) IStrategy
```

**描述**: 转换为 `IStrategy` 接口。

**返回**: `IStrategy` 接口实例

**示例**:
```zig
const engine = try BacktestEngine.init(allocator, .{});
defer engine.deinit();

const result = try engine.run(strategy.toStrategy(), candles);
```

---

## 完整示例

### 基础 AI 查询

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 创建 LLM 客户端
    const client = try zigQuant.LLMClient.init(allocator, .{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
        .api_key = std.posix.getenv("ANTHROPIC_API_KEY") orelse return error.NoApiKey,
        .temperature = 0.3,
    });
    defer client.deinit();

    // 2. 生成响应
    const response = try client.toInterface().generateText(
        "What are the key factors to consider when trading BTC?"
    );
    defer allocator.free(response);

    std.debug.print("AI Response:\n{s}\n", .{response});
}
```

### 使用 AIAdvisor

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 创建 LLM 客户端
    const client = try zigQuant.LLMClient.init(allocator, .{
        .provider = .openai,
        .model_id = "gpt-4o",
        .api_key = std.posix.getenv("OPENAI_API_KEY") orelse return error.NoApiKey,
    });
    defer client.deinit();

    // 2. 创建 Advisor
    var advisor = zigQuant.AIAdvisor.init(allocator, client.toInterface(), .{
        .min_confidence_threshold = 0.6,
        .max_retries = 2,
    });
    defer advisor.deinit();

    // 3. 获取建议
    const advice = try advisor.getAdvice(.{
        .pair = .{ .base = "ETH", .quote = "USDT" },
        .current_price = zigQuant.Decimal.fromFloat(2500.0),
        .price_change_24h = -0.03,
        .indicators = &.{
            .{ .name = "RSI", .value = 28.5, .interpretation = "oversold" },
            .{ .name = "MACD", .value = -15.2, .interpretation = "bearish but weakening" },
        },
        .recent_candles = &.{},
        .position = null,
    });

    std.debug.print("AI Trading Advice:\n", .{});
    std.debug.print("  Action: {s}\n", .{@tagName(advice.action)});
    std.debug.print("  Confidence: {d:.0}%\n", .{advice.confidence * 100});
    std.debug.print("  Reasoning: {s}\n", .{advice.reasoning});

    // 4. 查看统计
    const stats = advisor.getStats();
    std.debug.print("\nAdvisor Stats:\n", .{});
    std.debug.print("  Total Requests: {}\n", .{stats.total_requests});
    std.debug.print("  Success Rate: {d:.0}%\n", .{stats.success_rate * 100});
    std.debug.print("  Avg Latency: {d:.0}ms\n", .{stats.avg_latency_ms});
}
```

### 混合策略回测

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 加载历史数据
    const candles = try zigQuant.loadCandlesFromCSV(allocator, "data/btc_1h.csv");
    defer candles.deinit();

    // 2. 创建混合策略
    const strategy = try zigQuant.HybridAIStrategy.create(allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .timeframe = .h1,
        .ai_weight = 0.4,
        .technical_weight = 0.6,
        .min_combined_score = 0.65,
        .rsi_period = 14,
        .rsi_oversold = 30,
        .rsi_overbought = 70,
        .ai_config = .{
            .provider = .anthropic,
            .model_id = "claude-haiku",  // 使用低成本模型
            .api_key = std.posix.getenv("ANTHROPIC_API_KEY") orelse return error.NoApiKey,
            .temperature = 0.2,
        },
    });
    defer strategy.destroy();

    // 3. 运行回测
    const engine = try zigQuant.BacktestEngine.init(allocator, .{
        .initial_capital = 10000.0,
        .commission_rate = 0.001,
    });
    defer engine.deinit();

    const result = try engine.run(strategy.toStrategy(), candles);

    // 4. 输出结果
    std.debug.print("Hybrid AI Strategy Backtest Results:\n", .{});
    std.debug.print("  Total Return: {d:.2}%\n", .{result.total_return * 100});
    std.debug.print("  Sharpe Ratio: {d:.2}\n", .{result.sharpe_ratio});
    std.debug.print("  Max Drawdown: {d:.2}%\n", .{result.max_drawdown * 100});
    std.debug.print("  Win Rate: {d:.0}%\n", .{result.win_rate * 100});
    std.debug.print("  Total Trades: {}\n", .{result.total_trades});
}
```

---

## 错误类型

### AIError

```zig
pub const AIError = error{
    UnsupportedProvider,  // 不支持的 AI 提供商
    InvalidWeights,       // 权重配置无效
    InvalidConfig,        // 配置无效
    Timeout,              // 请求超时
    ApiError,             // API 返回错误
    ParseError,           // 响应解析失败
    RateLimited,          // 请求频率限制
    ConnectionFailed,     // 连接失败
};
```

---

## 相关文档

- [功能概览](./README.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)
- [Bug 追踪](./bugs.md)
- [变更日志](./changelog.md)

---

*最后更新: 2025-12-28*
