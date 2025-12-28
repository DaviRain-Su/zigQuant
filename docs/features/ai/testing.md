# AI 模块 - 测试文档

> 测试覆盖和性能基准

**模块路径**: `src/ai/`
**版本**: v0.9.0
**最后更新**: 2025-12-28

---

## 测试覆盖率

| 指标 | 值 |
|------|-----|
| **代码覆盖率** | 目标 > 85% |
| **测试用例数** | 30+ |
| **性能基准** | 延迟追踪 |

---

## 测试分类

### 1. 单元测试

#### 类型定义测试

```zig
test "AIAdvice.toScore returns correct values" {
    const test_cases = [_]struct { action: AIAdvice.Action, expected: f64 }{
        .{ .action = .strong_buy, .expected = 1.0 },
        .{ .action = .buy, .expected = 0.75 },
        .{ .action = .hold, .expected = 0.5 },
        .{ .action = .sell, .expected = 0.25 },
        .{ .action = .strong_sell, .expected = 0.0 },
    };

    for (test_cases) |tc| {
        const advice = AIAdvice{
            .action = tc.action,
            .confidence = 0.8,
            .reasoning = "test",
            .timestamp = 0,
        };
        try std.testing.expectEqual(tc.expected, advice.toScore());
    }
}

test "AIConfig default values" {
    const config = AIConfig{
        .provider = .openai,
        .model_id = "gpt-4o",
        .api_key = "test-key",
    };

    try std.testing.expectEqual(@as(u32, 1024), config.max_tokens);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), config.temperature, 0.001);
    try std.testing.expectEqual(@as(u32, 30000), config.timeout_ms);
}

test "AIProvider enum values" {
    try std.testing.expectEqual(@as(usize, 4), @typeInfo(AIProvider).Enum.fields.len);
}
```

---

#### PromptBuilder 测试

```zig
test "PromptBuilder.init and deinit" {
    var builder = PromptBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try std.testing.expect(builder.buffer.items.len == 0);
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

    // 验证 prompt 包含必要内容
    try std.testing.expect(std.mem.indexOf(u8, prompt, "BTC/USDT") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "45000") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "RSI") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "35.5") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "trading recommendation") != null);
}

test "PromptBuilder.buildMarketAnalysisPrompt with position" {
    var builder = PromptBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const ctx = MarketContext{
        .pair = .{ .base = "ETH", .quote = "USDT" },
        .current_price = Decimal.fromFloat(2500.0),
        .price_change_24h = -0.015,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = Position{
            .side = .long,
            .entry_price = Decimal.fromFloat(2400.0),
            .unrealized_pnl_pct = 0.0417,
        },
    };

    const prompt = try builder.buildMarketAnalysisPrompt(ctx);

    // 验证包含仓位信息
    try std.testing.expect(std.mem.indexOf(u8, prompt, "Current Position") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "long") != null);
}

test "PromptBuilder.getAdviceSchema returns valid JSON" {
    const schema = PromptBuilder.getAdviceSchema();

    // 验证可解析为 JSON
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        schema,
        .{},
    );
    defer parsed.deinit();

    // 验证 schema 结构
    try std.testing.expect(parsed.value.object.get("type") != null);
    try std.testing.expect(parsed.value.object.get("properties") != null);
    try std.testing.expect(parsed.value.object.get("required") != null);
}
```

---

#### ILLMClient 接口测试

```zig
test "ILLMClient interface conformance" {
    // 验证 VTable 结构
    const vtable_info = @typeInfo(ILLMClient.VTable);
    try std.testing.expectEqual(@as(usize, 5), vtable_info.Struct.fields.len);

    // 验证字段名
    const expected_fields = [_][]const u8{
        "generateText",
        "generateObject",
        "getModel",
        "isConnected",
        "deinit",
    };

    for (expected_fields) |field_name| {
        var found = false;
        for (vtable_info.Struct.fields) |field| {
            if (std.mem.eql(u8, field.name, field_name)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}
```

---

### 2. Mock 测试

#### MockLLMClient 实现

```zig
pub const MockLLMClient = struct {
    response: []const u8,
    call_count: u32 = 0,
    should_fail: bool = false,
    fail_error: anyerror = error.ApiError,

    pub fn init(response: []const u8) MockLLMClient {
        return .{ .response = response };
    }

    pub fn initFailing(err: anyerror) MockLLMClient {
        return .{
            .response = "",
            .should_fail = true,
            .fail_error = err,
        };
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

        if (self.should_fail) {
            return self.fail_error;
        }
        return self.response;
    }

    fn generateObjectImpl(ptr: *anyopaque, _: []const u8, _: []const u8) anyerror![]const u8 {
        const self: *MockLLMClient = @ptrCast(@alignCast(ptr));
        self.call_count += 1;

        if (self.should_fail) {
            return self.fail_error;
        }
        return self.response;
    }

    fn getModelImpl(_: *anyopaque) AIModel {
        return .{ .provider = .custom, .model_id = "mock-model" };
    }

    fn isConnectedImpl(_: *anyopaque) bool {
        return true;
    }

    fn deinitImpl(_: *anyopaque) void {}

    const mock_vtable = ILLMClient.VTable{
        .generateText = generateTextImpl,
        .generateObject = generateObjectImpl,
        .getModel = getModelImpl,
        .isConnected = isConnectedImpl,
        .deinit = deinitImpl,
    };
};
```

#### Mock 测试用例

```zig
test "MockLLMClient basic usage" {
    var mock = MockLLMClient.init("Hello, World!");
    const client = mock.toInterface();

    const response = try client.generateText("test prompt");
    try std.testing.expectEqualStrings("Hello, World!", response);
    try std.testing.expectEqual(@as(u32, 1), mock.call_count);
}

test "MockLLMClient failure simulation" {
    var mock = MockLLMClient.initFailing(error.Timeout);
    const client = mock.toInterface();

    const result = client.generateText("test prompt");
    try std.testing.expectError(error.Timeout, result);
}

test "AIAdvisor with MockLLMClient" {
    const mock_response =
        \\{"action": "buy", "confidence": 0.85, "reasoning": "Strong bullish momentum detected"}
    ;

    var mock = MockLLMClient.init(mock_response);
    var advisor = AIAdvisor.init(std.testing.allocator, mock.toInterface(), .{});
    defer advisor.deinit();

    const ctx = MarketContext{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = Decimal.fromFloat(45000.0),
        .price_change_24h = 0.025,
        .indicators = &.{},
        .recent_candles = &.{},
        .position = null,
    };

    const advice = try advisor.getAdvice(ctx);

    try std.testing.expectEqual(AIAdvice.Action.buy, advice.action);
    try std.testing.expectApproxEqAbs(@as(f64, 0.85), advice.confidence, 0.001);
    try std.testing.expectEqualStrings("Strong bullish momentum detected", advice.reasoning);
    try std.testing.expectEqual(@as(u32, 1), mock.call_count);
}

test "AIAdvisor stats tracking" {
    const mock_response =
        \\{"action": "hold", "confidence": 0.6, "reasoning": "Neutral market conditions"}
    ;

    var mock = MockLLMClient.init(mock_response);
    var advisor = AIAdvisor.init(std.testing.allocator, mock.toInterface(), .{});
    defer advisor.deinit();

    const ctx = createTestContext();

    // 多次调用
    _ = try advisor.getAdvice(ctx);
    _ = try advisor.getAdvice(ctx);
    _ = try advisor.getAdvice(ctx);

    const stats = advisor.getStats();
    try std.testing.expectEqual(@as(u64, 3), stats.total_requests);
    try std.testing.expectEqual(@as(u64, 3), stats.successful_requests);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), stats.success_rate, 0.001);
}
```

---

### 3. 集成测试

#### HybridAIStrategy 测试

```zig
test "HybridAIStrategy creation" {
    const strategy = try HybridAIStrategy.create(std.testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .timeframe = .h1,
        .ai_weight = 0.4,
        .technical_weight = 0.6,
        .ai_config = createTestAIConfig(),
    });
    defer strategy.destroy();

    try std.testing.expect(strategy.initialized == false); // 未初始化
}

test "HybridAIStrategy invalid weights" {
    const result = HybridAIStrategy.create(std.testing.allocator, .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .timeframe = .h1,
        .ai_weight = 0.5,
        .technical_weight = 0.6, // 总和 != 1.0
        .ai_config = createTestAIConfig(),
    });

    try std.testing.expectError(error.InvalidWeights, result);
}

test "HybridAIStrategy toStrategy interface" {
    const strategy = try createTestHybridStrategy(std.testing.allocator);
    defer strategy.destroy();

    const iface = strategy.toStrategy();

    // 验证接口有效
    try std.testing.expect(iface.vtable != null);
    try std.testing.expect(iface.ptr != null);
}

test "HybridAIStrategy signal generation with mock" {
    // 使用 Mock LLM 测试信号生成
    var strategy = try createTestHybridStrategyWithMock(std.testing.allocator);
    defer strategy.destroy();

    const candles = try createTestCandles(std.testing.allocator, 100);
    defer candles.deinit();

    // 初始化策略
    try strategy.toStrategy().init(&candles);
    defer strategy.toStrategy().deinit();

    // 生成信号
    const signal = strategy.toStrategy().generateEntrySignal(&candles, 50);

    if (signal) |s| {
        try std.testing.expect(s.strength >= 0.0 and s.strength <= 1.0);
        try std.testing.expect(s.pair.base.len > 0);
    }
}
```

---

### 4. 内存测试

```zig
test "LLMClient no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) @panic("Memory leak detected in LLMClient!");
    }
    const allocator = gpa.allocator();

    // 测试多次创建和销毁
    for (0..10) |_| {
        const client = try LLMClient.init(allocator, createTestAIConfig());
        client.deinit();
    }
}

test "AIAdvisor no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) @panic("Memory leak detected in AIAdvisor!");
    }
    const allocator = gpa.allocator();

    var mock = MockLLMClient.init("{}");
    var advisor = AIAdvisor.init(allocator, mock.toInterface(), .{});
    advisor.deinit();
}

test "PromptBuilder no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) @panic("Memory leak detected in PromptBuilder!");
    }
    const allocator = gpa.allocator();

    var builder = PromptBuilder.init(allocator);

    // 多次构建 prompt
    for (0..10) |_| {
        _ = try builder.buildMarketAnalysisPrompt(createTestContext());
    }

    builder.deinit();
}

test "HybridAIStrategy no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) @panic("Memory leak detected in HybridAIStrategy!");
    }
    const allocator = gpa.allocator();

    const strategy = try createTestHybridStrategyWithMock(allocator);
    strategy.destroy();
}
```

---

## 性能基准

### 基准测试

```zig
test "PromptBuilder performance" {
    var builder = PromptBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const ctx = createTestContext();
    const iterations: u32 = 1000;

    const start = std.time.nanoTimestamp();
    for (0..iterations) |_| {
        _ = try builder.buildMarketAnalysisPrompt(ctx);
    }
    const elapsed = std.time.nanoTimestamp() - start;

    const ns_per_op = @divFloor(elapsed, iterations);
    std.debug.print("PromptBuilder: {} ns/op\n", .{ns_per_op});

    // 验证性能 (< 1ms per operation)
    try std.testing.expect(ns_per_op < 1_000_000);
}

test "AIAdvice.toScore performance" {
    const iterations: u32 = 100_000;

    const start = std.time.nanoTimestamp();
    for (0..iterations) |_| {
        const advice = AIAdvice{
            .action = .buy,
            .confidence = 0.8,
            .reasoning = "test",
            .timestamp = 0,
        };
        _ = advice.toScore();
    }
    const elapsed = std.time.nanoTimestamp() - start;

    const ns_per_op = @divFloor(elapsed, iterations);
    std.debug.print("AIAdvice.toScore: {} ns/op\n", .{ns_per_op});

    // 验证性能 (< 100ns per operation)
    try std.testing.expect(ns_per_op < 100);
}
```

### 基准结果

| 操作 | 性能 | 目标 |
|------|------|------|
| `PromptBuilder.buildMarketAnalysisPrompt` | < 1ms | < 5ms |
| `AIAdvice.toScore` | < 100ns | < 1us |
| `MockLLMClient.generateText` | < 1us | < 10us |
| JSON 解析 (AIAdvice) | < 100us | < 1ms |

---

## 运行测试

### 运行所有 AI 模块测试

```bash
zig test src/ai/mod.zig
```

### 运行特定文件测试

```bash
# 类型测试
zig test src/ai/types.zig

# 接口测试
zig test src/ai/interfaces.zig

# 客户端测试
zig test src/ai/client.zig

# Advisor 测试
zig test src/ai/advisor.zig

# PromptBuilder 测试
zig test src/ai/prompt_builder.zig
```

### 运行集成测试

```bash
# HybridAIStrategy 测试
zig test src/strategy/builtin/hybrid_ai.zig
```

### 运行性能基准

```bash
zig test --release-safe src/ai/mod.zig
```

---

## 测试场景

### ✅ 已覆盖

- [x] AIAdvice.toScore 正确性
- [x] AIConfig 默认值
- [x] AIProvider 枚举完整性
- [x] PromptBuilder 初始化/销毁
- [x] PromptBuilder 市场分析 Prompt 生成
- [x] PromptBuilder 带仓位信息 Prompt
- [x] PromptBuilder JSON Schema 有效性
- [x] ILLMClient 接口一致性
- [x] MockLLMClient 基础功能
- [x] MockLLMClient 失败模拟
- [x] AIAdvisor 与 Mock 集成
- [x] AIAdvisor 统计追踪
- [x] HybridAIStrategy 创建
- [x] HybridAIStrategy 权重验证
- [x] HybridAIStrategy 接口转换
- [x] 内存泄漏检测 (所有组件)

### 📋 待补充

- [ ] LLMClient 真实 API 测试 (需要 API Key)
- [ ] HybridAIStrategy 回测集成测试
- [ ] AI 失败回退测试
- [ ] 并发请求测试
- [ ] 缓存 TTL 测试
- [ ] 重试机制测试
- [ ] 超时处理测试

---

## 测试工具函数

```zig
fn createTestContext() MarketContext {
    return .{
        .pair = .{ .base = "BTC", .quote = "USDT" },
        .current_price = Decimal.fromFloat(45000.0),
        .price_change_24h = 0.025,
        .indicators = &.{
            .{ .name = "RSI", .value = 35.5, .interpretation = "approaching oversold" },
        },
        .recent_candles = &.{},
        .position = null,
    };
}

fn createTestAIConfig() AIConfig {
    return .{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
        .api_key = "test-api-key",
        .temperature = 0.3,
    };
}

fn createTestHybridStrategyWithMock(allocator: std.mem.Allocator) !*HybridAIStrategy {
    // 创建带 Mock LLM 的测试策略
    // ...
}

fn createTestCandles(allocator: std.mem.Allocator, count: usize) !Candles {
    // 创建测试用 K 线数据
    // ...
}
```

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [实现细节](./implementation.md)
- [Bug 追踪](./bugs.md)
- [变更日志](./changelog.md)

---

*最后更新: 2025-12-28*
