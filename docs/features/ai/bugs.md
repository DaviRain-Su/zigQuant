# AI 模块 - Bug 追踪

> 已知问题和修复记录

**模块路径**: `src/ai/`
**版本**: v0.9.0
**最后更新**: 2025-12-28

---

## 当前状态

AI 模块处于开发阶段，目前没有已知的生产 Bug。本文档用于追踪开发过程中发现的问题。

| 状态 | 数量 |
|------|------|
| 🔴 Critical | 0 |
| 🟠 High | 0 |
| 🟡 Medium | 0 |
| 🟢 Low | 0 |
| ✅ Resolved | 0 |

---

## 已知 Bug

### 暂无

当前没有已知的 Bug。

---

## 潜在问题

以下是开发过程中需要注意的潜在问题，尚未确认为 Bug。

### Issue #1: API 超时处理

**状态**: 待验证
**严重性**: Medium
**发现日期**: 2025-12-28

**描述**:
在网络不稳定的情况下，AI API 调用可能超时。需要验证超时处理机制是否正确触发回退逻辑。

**可能影响**:
- HybridAIStrategy 可能无法正确回退到纯技术指标
- 用户可能看到未处理的超时错误

**验证步骤**:
```zig
test "timeout handling" {
    // 1. 配置一个极短的超时时间
    const config = AIConfig{
        .provider = .anthropic,
        .model_id = "claude-sonnet-4-5",
        .api_key = "test",
        .timeout_ms = 1, // 1ms，必然超时
    };

    // 2. 尝试调用
    // 3. 验证是否正确返回 error.Timeout
}
```

**缓解措施**:
- 确保 HybridAIStrategy 在 AI 失败时正确回退
- 添加超时重试机制

---

### Issue #2: JSON 解析容错

**状态**: 待验证
**严重性**: Medium
**发现日期**: 2025-12-28

**描述**:
如果 AI 返回的 JSON 格式不完全符合预期 Schema，解析可能失败。

**可能影响**:
- AIAdvisor.getAdvice 返回 ParseError
- 策略无法获取有效建议

**示例**:
```json
// 期望格式
{"action": "buy", "confidence": 0.8, "reasoning": "..."}

// 可能的非标准返回
{"action": "BUY", "confidence": "0.8", "reasoning": "..."}
```

**验证步骤**:
```zig
test "JSON parsing robustness" {
    const test_cases = [_][]const u8{
        // 标准格式
        \\{"action": "buy", "confidence": 0.8, "reasoning": "test"}
        ,
        // action 大写
        \\{"action": "BUY", "confidence": 0.8, "reasoning": "test"}
        ,
        // confidence 字符串
        \\{"action": "buy", "confidence": "0.8", "reasoning": "test"}
        ,
    };

    for (test_cases) |json| {
        // 验证解析是否成功或返回合理错误
    }
}
```

**缓解措施**:
- 使用 JSON Schema 强制输出格式
- 添加解析容错逻辑

---

### Issue #3: 内存泄漏风险

**状态**: 待验证
**严重性**: High
**发现日期**: 2025-12-28

**描述**:
AIAdvisor.getAdvice 返回的 reasoning 字符串是动态分配的，调用者需要正确释放。

**可能影响**:
- 长时间运行时内存持续增长
- 最终导致 OOM

**风险代码**:
```zig
pub fn getAdvice(self: *AIAdvisor, ctx: MarketContext) !AIAdvice {
    // ...
    const advice = AIAdvice{
        // ...
        .reasoning = try self.allocator.dupe(u8, parsed.value.reasoning),
        // ^^^^ 这个需要调用者释放
    };
    return advice;
}
```

**缓解措施**:
- 文档明确说明内存所有权
- 考虑使用 Arena Allocator
- 提供 AIAdvice.deinit 方法

---

## 已修复的 Bug

### 暂无

---

## 报告 Bug

发现 Bug 请提供以下信息：

### 必需信息

1. **标题**: 简短描述问题
2. **严重性**: Critical / High / Medium / Low
3. **复现步骤**:
   ```zig
   // 最小复现代码
   ```
4. **预期行为**: 描述期望的结果
5. **实际行为**: 描述实际发生的情况

### 可选信息

6. **环境信息**:
   - Zig 版本
   - 操作系统
   - AI Provider 和 Model

7. **错误信息**: 完整的错误输出或堆栈跟踪

8. **相关日志**: 如果有的话

### 严重性定义

| 级别 | 定义 | 示例 |
|------|------|------|
| **Critical** | 系统崩溃或数据损坏 | 段错误、内存损坏 |
| **High** | 核心功能无法使用 | 无法获取 AI 建议 |
| **Medium** | 功能受限但有变通方法 | 特定配置下超时 |
| **Low** | 小问题或优化建议 | 日志格式问题 |

---

## Bug 修复流程

1. **报告** - 创建 Issue 描述问题
2. **确认** - 维护者确认并分类
3. **分析** - 定位根本原因
4. **修复** - 实现修复方案
5. **测试** - 添加回归测试
6. **验证** - 确认修复有效
7. **发布** - 包含在下个版本

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)
- [变更日志](./changelog.md)

---

*最后更新: 2025-12-28*
