# v0.9.0 - AI 策略集成 & 引擎架构统一

**版本**: 0.9.0 → 0.9.1
**代号**: AI-Powered Trading + Unified Engine
**状态**: ✅ 已完成
**完成日期**: 2025-12-29

---

## 版本概述

v0.9.0 引入 AI 辅助交易决策能力，v0.9.1 完成引擎架构统一，将所有运行器（Strategy、Backtest、Live）整合到 `src/engine/runners/` 目录下，提供统一的 API 访问。

### 核心价值

1. **智能决策增强** - AI 分析市场数据，提供交易建议
2. **OpenAI 兼容** - 支持 OpenAI、LM Studio、Ollama、DeepSeek 等
3. **混合策略** - 结合技术指标和 AI 建议的加权决策
4. **容错设计** - AI 失败时自动回退到纯技术指标
5. **统一引擎架构** - 所有运行器使用一致的模式和 API (v0.9.1)

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

### 2. LLMClient - OpenAI 兼容客户端

基于 `openai-zig` 的具体实现，支持所有 OpenAI 兼容 API：

- **OpenAI** - GPT-4o, GPT-4, o1, o3 系列
- **LM Studio** - 本地模型服务 (http://127.0.0.1:1234)
- **Ollama** - 本地模型服务 (http://localhost:11434)
- **DeepSeek** - 第三方 API (https://api.deepseek.com)
- **自定义** - 任何 OpenAI 兼容 API

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
**状态**: ✅ 已完成
**文档**: [STORY_046_AI_STRATEGY.md](./STORY_046_AI_STRATEGY.md)

#### 验收标准

- [x] ILLMClient 接口 (VTable 模式)
- [x] OpenAI 兼容客户端实现
- [x] AIAdvisor 结构化交易建议
- [x] HybridAIStrategy 混合策略
- [x] 完整单元测试
- [x] 示例代码 (examples/33_openai_chat.zig)

---

## 依赖

### openai-zig

```zig
// build.zig.zon
.openai_zig = .{
    .url = "https://github.com/DaviRain-Su/openai-zig/archive/refs/heads/master.tar.gz",
    .hash = "openai_zig-0.0.0-xCfcQBnxBQDkrxZmwJkZsZgZP6KOpZU7qqlOqjfpseHO",
},
```

**核心 API**:
- `OpenAI.init()` - 创建客户端
- `chat.completions.create()` - 聊天补全
- `response_format: .json_schema` - JSON Schema 结构化输出
- 支持所有 OpenAI 兼容 API

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
└── 33_openai_chat.zig   # OpenAI 聊天示例
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

### v1.0.0+ 规划

1. **多模型投票** - 多个 AI 模型投票决策
2. **Anthropic/Google 支持** - 扩展到更多提供商
3. **RAG 集成** - 检索增强生成
4. **响应缓存** - 减少 API 调用成本

---

---

## v0.9.1 - 引擎架构统一

### 核心变更

v0.9.1 完成了引擎架构的统一工作：

#### Step 1: Grid Runner 移除 ✅
- 删除 `grid_runner.zig`
- Grid 策略通过 `StrategyRunner` + `GridStrategy` 运行
- 更新 REST API (`/api/v2/grid` → `/api/v2/strategy`)

#### Step 2: Live Runner 迁移 ✅
- 创建 `src/engine/runners/live_runner.zig` (~760 行)
- 包装 `LiveTradingEngine` 为统一的运行器模式
- 添加 `live_runners` HashMap 到 `EngineManager`
- 新增 `/api/v2/live` REST API 端点

#### Step 3: Paper Trading 评估 ✅
- 分析 `PaperTradingEngine` 与 `StrategyRunner` 的关系
- 决策：保持两者独立，服务不同用途
- `PaperTradingEngine` - 订单执行模拟
- `StrategyRunner` (paper mode) - 策略信号生成

### 新增组件

#### LiveRunner (`src/engine/runners/live_runner.zig`)

```zig
pub const LiveRunner = struct {
    allocator: Allocator,
    id: []const u8,
    request: LiveRequest,
    status: LiveStatus,
    stats: LiveStats,
    engine: ?LiveTradingEngine,
    // ...

    pub fn start(self: *Self) !void;
    pub fn stop(self: *Self) !void;
    pub fn pause(self: *Self) !void;
    pub fn unpause(self: *Self) !void;
    pub fn submitOrder(self: *Self, request: OrderRequest) !OrderResult;
    pub fn subscribe(self: *Self, symbol: []const u8) !void;
};
```

### 新增 API 端点

```
Live Trading:
  GET  /api/v2/live           # 列出所有实时交易会话
  POST /api/v2/live           # 启动会话
  GET  /api/v2/live/:id       # 会话详情
  DELETE /api/v2/live/:id     # 停止会话
  POST /api/v2/live/:id/pause    # 暂停
  POST /api/v2/live/:id/resume   # 恢复
  POST /api/v2/live/:id/subscribe  # 订阅交易对
```

### 架构变更

**之前 (v0.9.0)**:
```
src/engine/
├── manager.zig
└── runners/
    ├── strategy_runner.zig
    └── backtest_runner.zig

src/trading/
├── live_engine.zig  ← 独立
└── paper_engine.zig ← 独立
```

**之后 (v0.9.1)**:
```
src/engine/
├── manager.zig      # 管理所有运行器
└── runners/
    ├── strategy_runner.zig   # 所有策略 (含 Grid)
    ├── backtest_runner.zig   # 回测作业
    └── live_runner.zig       # 实时交易会话 (新增)

src/trading/
├── live_engine.zig   # 被 LiveRunner 包装
└── paper_trading.zig # 独立使用或与策略组合
```

### 测试结果

- ✅ **776/776 单元测试通过**
- ✅ **零内存泄漏**

---

## 相关文档

- [Story 046: AI 策略集成](./STORY_046_AI_STRATEGY.md)
- [AI 模块 API](../../features/ai/README.md)
- [实现细节](../../features/ai/implementation.md)
- [Live Trading 文档](../../features/live-trading/README.md)
- [Release Notes](../../releases/RELEASE_v0.9.0.md)

---

*最后更新: 2025-12-29*
