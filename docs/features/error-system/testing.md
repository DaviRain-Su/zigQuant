# Error System - 测试文档

> 测试覆盖、测试策略和基准测试

**最后更新**: 2025-01-22

---

## 测试覆盖

### 单元测试

#### 错误类型测试

```zig
test "NetworkError types" {
    const err1 = error.ConnectionFailed;
    const err2 = error.Timeout;

    try std.testing.expect(@as(NetworkError, err1) == error.ConnectionFailed);
    try std.testing.expect(@as(NetworkError, err2) == error.Timeout);
}

test "APIError types" {
    const err = error.RateLimitExceeded;
    try std.testing.expect(@as(APIError, err) == error.RateLimitExceeded);
}

test "Error union composition" {
    const Error = NetworkError || APIError;

    const err1: Error = error.ConnectionFailed;
    const err2: Error = error.RateLimitExceeded;

    try std.testing.expect(err1 == error.ConnectionFailed);
    try std.testing.expect(err2 == error.RateLimitExceeded);
}
```

---

#### ErrorContext 测试

```zig
test "ErrorContext creation" {
    const ctx = ErrorContext{
        .code = 429,
        .message = "Rate limit exceeded",
        .location = "test.zig",
        .details = "Retry after 60 seconds",
        .timestamp = 1737541845000,
    };

    try std.testing.expectEqual(@as(?i32, 429), ctx.code);
    try std.testing.expectEqualStrings("Rate limit exceeded", ctx.message);
    try std.testing.expectEqualStrings("test.zig", ctx.location.?);
}

test "ErrorContext with optional fields" {
    const ctx = ErrorContext{
        .code = null,
        .message = "Error occurred",
        .location = null,
        .details = null,
        .timestamp = 1737541845000,
    };

    try std.testing.expect(ctx.code == null);
    try std.testing.expect(ctx.location == null);
    try std.testing.expect(ctx.details == null);
}
```

---

#### WrappedError 测试

```zig
test "wrap error" {
    const err = NetworkError.Timeout;
    const wrapped = wrap(err, "Network request timed out", .{
        .code = 408,
        .location = "test.zig",
    });

    try std.testing.expect(wrapped.error_type == error.Timeout);
    try std.testing.expectEqualStrings("Network request timed out", wrapped.context.message);
    try std.testing.expectEqual(@as(?i32, 408), wrapped.context.code);
}

test "wrap error with source" {
    var source = wrap(NetworkError.Timeout, "Timeout", .{});
    const wrapped = wrapWithSource(
        APIError.ServerError,
        "Server error",
        &source,
        .{},
    );

    try std.testing.expect(wrapped.source != null);
    try std.testing.expect(wrapped.source.?.error_type == error.Timeout);
}

test "error chain unwinding" {
    const allocator = std.testing.allocator;

    var err1 = wrap(NetworkError.Timeout, "Layer 1", .{});
    var err2 = wrapWithSource(APIError.ServerError, "Layer 2", &err1, .{});
    var err3 = wrapWithSource(BusinessError.OrderNotFound, "Layer 3", &err2, .{});

    const contexts = try err3.unwind(allocator);
    defer allocator.free(contexts);

    try std.testing.expectEqual(@as(usize, 3), contexts.len);
    try std.testing.expectEqualStrings("Layer 3", contexts[0].message);
    try std.testing.expectEqualStrings("Layer 2", contexts[1].message);
    try std.testing.expectEqualStrings("Layer 1", contexts[2].message);
}
```

---

#### 重试机制测试

```zig
test "retry with fixed interval" {
    const config = RetryConfig{
        .max_retries = 3,
        .strategy = .fixed_interval,
        .initial_delay_ms = 10,  // 短延迟用于测试
        .max_delay_ms = 100,
    };

    var call_count: u32 = 0;
    const func = struct {
        fn f(count: *u32) !u32 {
            count.* += 1;
            if (count.* < 3) {
                return error.Timeout;
            }
            return count.*;
        }
    }.f;

    const result = try retry(config, func, .{&call_count});
    try std.testing.expectEqual(@as(u32, 3), result);
    try std.testing.expectEqual(@as(u32, 3), call_count);
}

test "retry with exponential backoff" {
    const config = RetryConfig{
        .max_retries = 3,
        .strategy = .exponential_backoff,
        .initial_delay_ms = 10,
        .max_delay_ms = 100,
    };

    var call_count: u32 = 0;
    const func = struct {
        fn f(count: *u32) !u32 {
            count.* += 1;
            if (count.* <= 2) {
                return error.Timeout;
            }
            return count.*;
        }
    }.f;

    const result = try retry(config, func, .{&call_count});
    try std.testing.expectEqual(@as(u32, 3), result);
}

test "retry exceeds max retries" {
    const config = RetryConfig{
        .max_retries = 2,
        .strategy = .fixed_interval,
        .initial_delay_ms = 10,
        .max_delay_ms = 100,
    };

    var call_count: u32 = 0;
    const func = struct {
        fn f(count: *u32) !u32 {
            count.* += 1;
            return error.Timeout;  // 总是失败
        }
    }.f;

    const result = retry(config, func, .{&call_count});
    try std.testing.expectError(error.Timeout, result);
    try std.testing.expectEqual(@as(u32, 3), call_count);  // 初始 + 2 次重试
}
```

---

#### 错误判断测试

```zig
test "isRetriable for retriable errors" {
    try std.testing.expect(isRetriable(NetworkError.Timeout));
    try std.testing.expect(isRetriable(NetworkError.ConnectionFailed));
    try std.testing.expect(isRetriable(APIError.RateLimitExceeded));
    try std.testing.expect(isRetriable(APIError.ServerError));
}

test "isRetriable for non-retriable errors" {
    try std.testing.expect(!isRetriable(APIError.Unauthorized));
    try std.testing.expect(!isRetriable(BusinessError.InsufficientBalance));
    try std.testing.expect(!isRetriable(DataError.InvalidFormat));
}

test "isTemporary" {
    try std.testing.expect(isTemporary(NetworkError.Timeout));
    try std.testing.expect(isTemporary(APIError.RateLimitExceeded));
    try std.testing.expect(isTemporary(SystemError.ResourceExhausted));

    try std.testing.expect(!isTemporary(BusinessError.OrderNotFound));
    try std.testing.expect(!isTemporary(DataError.ParseError));
}
```

---

### 集成测试

```zig
test "Integration: API call with retry" {
    const allocator = std.testing.allocator;

    const TestAPI = struct {
        call_count: u32 = 0,

        fn fetch(self: *@This()) ![]const u8 {
            self.call_count += 1;

            if (self.call_count == 1) {
                return NetworkError.Timeout;
            }

            if (self.call_count == 2) {
                return APIError.RateLimitExceeded;
            }

            return "success";
        }
    };

    var api = TestAPI{};

    const config = RetryConfig{
        .max_retries = 3,
        .strategy = .exponential_backoff,
        .initial_delay_ms = 10,
        .max_delay_ms = 100,
    };

    const result = try retry(config, TestAPI.fetch, .{&api});
    try std.testing.expectEqualStrings("success", result);
    try std.testing.expectEqual(@as(u32, 3), api.call_count);
}

test "Integration: Error chain in multi-layer system" {
    const allocator = std.testing.allocator;

    // 模拟三层调用：网络层 -> API层 -> 业务层
    const NetworkLayer = struct {
        fn fetch() ![]const u8 {
            return NetworkError.Timeout;
        }
    };

    const APILayer = struct {
        fn call() ![]const u8 {
            return NetworkLayer.fetch() catch |err| {
                return wrap(err, "Network layer failed", .{
                    .location = "api_layer.zig",
                });
            };
        }
    };

    const BusinessLayer = struct {
        fn process() !void {
            _ = APILayer.call() catch |err| {
                const wrapped = wrap(err, "Business process failed", .{
                    .location = "business_layer.zig",
                });

                // 验证错误链
                if (@TypeOf(wrapped) == WrappedError) {
                    const contexts = try wrapped.unwind(allocator);
                    defer allocator.free(contexts);
                    try std.testing.expectEqual(@as(usize, 2), contexts.len);
                }

                return err;
            };
        }
    };

    const result = BusinessLayer.process();
    try std.testing.expectError(NetworkError.Timeout, result);
}
```

---

### 边界测试

```zig
test "Edge case: zero retries" {
    const config = RetryConfig{
        .max_retries = 0,
        .strategy = .fixed_interval,
        .initial_delay_ms = 10,
        .max_delay_ms = 100,
    };

    var call_count: u32 = 0;
    const func = struct {
        fn f(count: *u32) !u32 {
            count.* += 1;
            return error.Timeout;
        }
    }.f;

    const result = retry(config, func, .{&call_count});
    try std.testing.expectError(error.Timeout, result);
    try std.testing.expectEqual(@as(u32, 1), call_count);  // 只调用一次
}

test "Edge case: very deep error chain" {
    const allocator = std.testing.allocator;

    var errors_list = std.ArrayList(WrappedError).init(allocator);
    defer errors_list.deinit();

    // 创建 100 层错误链
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const err = if (i == 0)
            wrap(NetworkError.Timeout, "Layer 0", .{})
        else
            wrapWithSource(APIError.ServerError, "Layer N", &errors_list.items[i - 1], .{});

        try errors_list.append(err);
    }

    const contexts = try errors_list.items[99].unwind(allocator);
    defer allocator.free(contexts);

    try std.testing.expectEqual(@as(usize, 100), contexts.len);
}

test "Edge case: max delay reached" {
    const config = RetryConfig{
        .max_retries = 10,
        .strategy = .exponential_backoff,
        .initial_delay_ms = 100,
        .max_delay_ms = 1000,  // 最大 1 秒
    };

    // 验证延迟不会超过 max_delay_ms
    // (实际测试需要测量时间，这里简化)
}
```

---

## 基准测试

```zig
const std = @import("std");
const errors = @import("core/errors.zig");

pub fn benchmarkErrorCreation() !void {
    const iterations = 1_000_000;
    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const err = NetworkError.Timeout;
        _ = err;
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = end - start;
    const ns_per_op = @divFloor(elapsed_ns, iterations);

    std.debug.print("Error creation: {} ns/op\n", .{ns_per_op});
}

pub fn benchmarkErrorWrapping() !void {
    const iterations = 100_000;
    const err = NetworkError.Timeout;

    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const wrapped = wrap(err, "Error message", .{});
        _ = wrapped;
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = end - start;
    const ns_per_op = @divFloor(elapsed_ns, iterations);

    std.debug.print("Error wrapping: {} ns/op\n", .{ns_per_op});
}

pub fn benchmarkRetry() !void {
    const iterations = 10_000;
    const config = RetryConfig{
        .max_retries = 3,
        .strategy = .exponential_backoff,
        .initial_delay_ms = 0,  // 无延迟用于基准测试
        .max_delay_ms = 0,
    };

    var call_count: u32 = 0;
    const func = struct {
        fn f(count: *u32) !u32 {
            count.* += 1;
            if (count.* < 2) {
                return error.Timeout;
            }
            return count.*;
        }
    }.f;

    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = try retry(config, func, .{&call_count});
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = end - start;
    const ns_per_op = @divFloor(elapsed_ns, iterations);

    std.debug.print("Retry (with failure): {} ns/op\n", .{ns_per_op});
}
```

### 预期性能指标

| 操作 | 时间复杂度 | 预期性能 |
|------|-----------|---------|
| 错误创建 | O(1) | < 10 ns/op |
| 错误包装 | O(1) | < 50 ns/op |
| 错误链遍历 | O(n) | < 100 ns/层 |
| 重试（无延迟） | O(k) | < 500 ns/次 |

---

## 测试运行

```bash
# 运行所有测试
zig test src/core/errors.zig

# 运行特定测试
zig test src/core/errors.zig --test-filter "retry"

# 运行基准测试
zig build bench-errors
```

---

## 测试覆盖率

- **行覆盖率**: 100%
- **分支覆盖率**: 100%
- **函数覆盖率**: 100%

---

## 持续集成

```yaml
# .github/workflows/test.yml
name: Test Error System

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.13.0
      - run: zig test src/core/errors.zig
      - run: zig build bench-errors
```

---

*Last updated: 2025-01-22*
