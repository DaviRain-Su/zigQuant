# Error System - Bug 追踪

> 已知问题、修复记录和解决方案

**最后更新**: 2025-01-22

---

## 当前已知问题

### 无重大问题

Error System 当前没有已知的重大 Bug。

---

## 已修复问题

_暂无历史记录_

---

## 潜在改进

### 1. 错误链内存管理

**描述**: 当前 `WrappedError` 使用指针，需要手动管理内存

**影响**:
- 需要调用方负责分配和释放
- 容易造成内存泄漏
- 错误链深度过大时内存占用较高

**解决方案**:
- 使用 Arena Allocator 简化内存管理
- 添加 `ErrorChain` 辅助类型
- 考虑使用栈分配的有限深度错误链

**优先级**: 中

**示例**:
```zig
pub const ErrorChain = struct {
    arena: std.heap.ArenaAllocator,
    root: ?*WrappedError,

    pub fn init(allocator: Allocator) ErrorChain {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .root = null,
        };
    }

    pub fn deinit(self: *ErrorChain) void {
        self.arena.deinit();
    }

    pub fn wrap(self: *ErrorChain, err: anyerror, msg: []const u8) !void {
        const allocator = self.arena.allocator();
        const wrapped = try allocator.create(WrappedError);
        wrapped.* = errors.wrap(err, msg, .{});
        wrapped.source = self.root;
        self.root = wrapped;
    }
};
```

---

### 2. 重试策略扩展

**描述**: 当前仅支持固定间隔和指数退避

**影响**:
- 某些场景需要更复杂的重试策略
- 例如：Jitter（抖动）、自适应延迟

**解决方案**:
- 添加 `RetryStrategy.exponential_backoff_with_jitter`
- 添加自定义重试条件函数

**优先级**: 低

**示例**:
```zig
pub const RetryStrategy = enum {
    fixed_interval,
    exponential_backoff,
    exponential_backoff_with_jitter,  // 添加抖动
};

pub const RetryConfig = struct {
    max_retries: u32,
    strategy: RetryStrategy,
    initial_delay_ms: u64,
    max_delay_ms: u64,
    should_retry_fn: ?*const fn (err: anyerror) bool,  // 自定义条件
};
```

---

### 3. 错误聚合

**描述**: 无法方便地处理多个错误

**影响**:
- 批量操作时难以收集所有错误
- 需要手动管理错误列表

**解决方案**:
- 添加 `ErrorList` 类型
- 支持错误聚合和批量报告

**优先级**: 低

**示例**:
```zig
pub const ErrorList = struct {
    errors: std.ArrayList(WrappedError),

    pub fn init(allocator: Allocator) ErrorList {
        return .{ .errors = std.ArrayList(WrappedError).init(allocator) };
    }

    pub fn add(self: *ErrorList, err: WrappedError) !void {
        try self.errors.append(err);
    }

    pub fn hasErrors(self: *const ErrorList) bool {
        return self.errors.items.len > 0;
    }
};
```

---

## 边界情况

### 1. 空错误消息

**场景**: 创建错误时消息为空字符串

```zig
const ctx = ErrorContext{
    .code = 500,
    .message = "",  // 空消息
    .location = null,
    .details = null,
    .timestamp = std.time.timestamp(),
};
```

**状态**: ✅ 正常工作

**说明**: 允许空消息，但不推荐。建议始终提供有意义的错误消息。

---

### 2. 极深的错误链

**场景**: 错误链深度超过 100 层

```zig
var chain: ?*WrappedError = null;
var i: usize = 0;
while (i < 1000) : (i += 1) {
    const err = try allocator.create(WrappedError);
    err.* = wrap(NetworkError.Timeout, "Layer", .{});
    err.source = chain;
    chain = err;
}
```

**状态**: ⚠️ 可能栈溢出

**说明**:
- `unwind()` 使用递归，深度过大可能栈溢出
- 建议限制错误链深度 < 50 层
- 考虑使用迭代而非递归实现 `unwind()`

**解决方案**:
```zig
pub fn unwind(self: *const WrappedError, allocator: Allocator) ![]ErrorContext {
    var contexts = std.ArrayList(ErrorContext).init(allocator);
    var current: ?*const WrappedError = self;
    var depth: usize = 0;
    const MAX_DEPTH = 100;

    while (current) |err| {
        if (depth >= MAX_DEPTH) break;  // 防止无限循环
        try contexts.append(err.context);
        current = err.source;
        depth += 1;
    }

    return contexts.toOwnedSlice();
}
```

---

### 3. 重试次数为 0

**场景**: `max_retries = 0`

```zig
const config = RetryConfig{
    .max_retries = 0,
    .strategy = .fixed_interval,
    .initial_delay_ms = 1000,
    .max_delay_ms = 10000,
};
```

**状态**: ✅ 正常工作

**说明**: 只执行一次，不重试。符合预期。

---

### 4. 并发重试

**场景**: 多个线程同时调用 `retry()`

```zig
var threads: [10]std.Thread = undefined;
for (&threads) |*thread| {
    thread.* = try std.Thread.spawn(.{}, retry, .{ config, fetchData, .{} });
}
```

**状态**: ✅ 正常工作

**说明**:
- `retry()` 本身不使用共享状态，线程安全
- 被调用的函数需要自行保证线程安全

---

## 性能问题

### 1. 错误包装开销

**描述**: 每次包装错误都会创建新的 `ErrorContext`

**影响**:
- 热路径上频繁包装会影响性能
- 内存分配开销

**解决方案**:
- 仅在必要时包装（如跨模块边界）
- 使用栈分配的 `ErrorContext`
- 避免在循环中包装错误

**优先级**: 低

---

### 2. 字符串拷贝

**描述**: 错误消息使用切片，可能指向临时内存

**影响**:
- 需要确保消息生命周期
- 可能需要拷贝字符串

**解决方案**:
- 使用字符串常量（编译时分配）
- 使用 Arena Allocator 管理字符串生命周期

**优先级**: 低

---

## 报告 Bug

如果发现新的 Bug，请按以下格式报告：

### Bug 模板

```markdown
### Bug 标题

**描述**: 简要描述问题

**复现步骤**:
1. 步骤 1
2. 步骤 2
3. ...

**预期行为**: 应该发生什么

**实际行为**: 实际发生了什么

**代码示例**:
```zig
// 最小复现代码
const err = NetworkError.Timeout;
const wrapped = wrap(err, "message", .{});
// ...
```

**环境**:
- Zig 版本: 0.13.0
- 操作系统: Linux/macOS/Windows
- zigQuant 版本: v0.1.0

**严重程度**: 低/中/高/致命
```

---

## 测试清单

发布前必须通过以下测试：

- [ ] 所有单元测试通过
- [ ] 边界测试通过（空消息、极深错误链）
- [ ] 集成测试通过（多层调用、重试）
- [ ] 基准测试性能达标
- [ ] 内存泄漏检查通过
- [ ] 并发测试通过

---

## 相关文档

- [测试文档](./testing.md) - 完整的测试覆盖
- [实现细节](./implementation.md) - 算法说明
- [API 参考](./api.md) - 完整 API 文档

---

*Last updated: 2025-01-22*
