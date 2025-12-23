# Error System - 错误处理系统

> 统一的错误处理、错误链、重试机制

**状态**: ✅ 已完成
**版本**: v0.1.0
**Story**: [003-error-system](../../../stories/v0.1-foundation/003-error-system.md)
**最后更新**: 2025-12-23

---

## 📋 概述

Error System 提供统一的错误处理框架，支持错误分类、上下文信息、错误链和自动重试机制。

### 为什么需要 Error System？

量化交易系统面临多种错误场景：
- 网络超时、连接失败
- API 限流、认证失败
- 数据解析错误、格式不匹配
- 业务逻辑错误（如余额不足）
- 系统资源不足

### 核心特性

- ✅ **5 大错误类别**: Network, API, Data, Business, System
- ✅ **错误上下文**: 包含代码、消息、位置、详情、时间戳
- ✅ **错误链**: 支持错误包装和源错误追踪
- ✅ **重试机制**: 固定间隔、指数退避
- ✅ **类型安全**: 利用 Zig 的错误联合类型

---

## 🚀 快速开始

### 基本使用

```zig
const std = @import("std");
const errors = @import("core/errors.zig");

pub fn fetchData(url: []const u8) ![]const u8 {
    // 网络请求
    const response = http.get(url) catch |err| {
        return errors.NetworkError.ConnectionFailed;
    };

    // API 错误检查
    if (response.status_code != 200) {
        return errors.APIError.RateLimitExceeded;
    }

    return response.body;
}

pub fn parseData(data: []const u8) !Order {
    const order = json.parse(data) catch |err| {
        return errors.DataError.InvalidFormat;
    };

    return order;
}
```

### 错误上下文

```zig
const ctx = errors.ErrorContext{
    .code = 429,
    .message = "Rate limit exceeded",
    .location = @src().file,
    .details = "Retry after 60 seconds",
    .timestamp = std.time.timestamp(),
};

try logger.logError(ctx);
```

### 错误包装

```zig
pub fn processOrder(order_id: []const u8) !void {
    const order = fetchOrder(order_id) catch |err| {
        // 简单包装
        return errors.wrap(err, "Failed to fetch order");
    };

    // 或使用带错误码的包装
    const data = fetchData() catch |err| {
        return errors.wrapWithCode(err, 500, "Failed to fetch data");
    };

    // 处理订单...
}
```

### 重试机制

```zig
const retry_config = errors.RetryConfig{
    .max_retries = 3,
    .strategy = .exponential_backoff,
    .initial_delay_ms = 1000,
    .max_delay_ms = 10000,
};

const result = try errors.retry(retry_config, fetchDataWithRetry, .{url});
```

---

## 📚 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 🔧 核心 API

```zig
/// 5 大错误类别
pub const NetworkError = error{
    ConnectionFailed,
    Timeout,
    DNSResolutionFailed,
    SSLError,
};

pub const APIError = error{
    Unauthorized,
    RateLimitExceeded,
    InvalidRequest,
    ServerError,
    BadRequest,
    NotFound,
};

pub const DataError = error{
    InvalidFormat,
    ParseError,
    ValidationFailed,
    MissingField,
    TypeMismatch,
};

pub const BusinessError = error{
    InsufficientBalance,
    OrderNotFound,
    InvalidOrderStatus,
    PositionNotFound,
    InvalidQuantity,
    MarketClosed,
};

pub const SystemError = error{
    OutOfMemory,
    FileNotFound,
    PermissionDenied,
    ResourceExhausted,
};

/// 错误上下文
pub const ErrorContext = struct {
    code: ?i32,
    message: []const u8,
    location: ?[]const u8,
    details: ?[]const u8,
    timestamp: i64,
};

/// 包装错误（带源错误）
pub const WrappedError = struct {
    error_type: anyerror,
    context: ErrorContext,
    source: ?*WrappedError,
};

/// 重试策略
pub const RetryStrategy = enum {
    fixed_interval,
    exponential_backoff,
};

pub const RetryConfig = struct {
    max_retries: u32,
    strategy: RetryStrategy,
    initial_delay_ms: u64,
    max_delay_ms: u64,
};

/// 重试执行
pub fn retry(
    config: RetryConfig,
    func: anytype,
    args: anytype,
) !@TypeOf(func).ReturnType {
    // 实现见 implementation.md
}

/// 包装错误
pub fn wrap(err: anyerror, message: []const u8) WrappedError;
pub fn wrapWithCode(err: anyerror, code: i32, message: []const u8) WrappedError;
pub fn wrapWithSource(err: anyerror, message: []const u8, source: *const WrappedError) WrappedError;
```

---

## 📝 最佳实践

### ✅ DO

```zig
// 1. 使用具体的错误类型
return errors.APIError.RateLimitExceeded;

// 2. 添加错误上下文
const ctx = errors.ErrorContext{
    .code = response.status_code,
    .message = "API request failed",
    .location = @src().file,
    .details = response.body,
    .timestamp = std.time.timestamp(),
};

// 3. 包装错误保留源错误
fetchData() catch |err| {
    return errors.wrap(err, "Failed to fetch market data");
};

// 4. 对临时错误使用重试
const result = try errors.retry(retry_config, fetchData, .{});
```

### ❌ DON'T

```zig
// 1. 避免吞掉错误
fetchData() catch {};  // ❌ 错误被忽略

// 2. 避免过度包装
// ❌ 每一层都包装会导致错误链过长
// 使用 wrapWithSource 创建错误链，而不是嵌套 wrap

// 3. 避免对所有错误都重试
// ❌ 业务错误不应该重试
retry(config, createOrder, .{});  // 如果余额不足，重试无意义
```

---

## 🎯 使用场景

### ✅ 适用

- **网络请求**: 超时、连接失败需要重试
- **API 调用**: 限流、临时错误处理
- **数据解析**: 格式错误、验证失败
- **业务逻辑**: 余额不足、订单状态错误
- **错误日志**: 记录完整的错误上下文

### ❌ 不适用

- 正常的控制流（使用 `if` 而非错误）
- 性能关键路径（错误处理有开销）
- 简单的成功/失败判断（使用 `bool` 即可）

---

## 📊 性能指标

- **错误创建**: O(1)
- **错误包装**: O(1)
- **错误链遍历**: O(n)，n 为链长度
- **重试机制**: O(k)，k 为重试次数
- **内存占用**: ErrorContext ~64 bytes

---

## 💡 未来改进

- [ ] 支持错误聚合（多个错误合并）
- [ ] 错误统计和监控
- [ ] 自定义重试条件
- [ ] 错误恢复策略（fallback）
- [ ] 错误国际化（i18n）

---

*Last updated: 2025-12-23*
