# Error System - 实现细节

> 内部实现说明和设计决策

**最后更新**: 2025-01-22

---

## 核心数据结构

### ErrorContext

```zig
pub const ErrorContext = struct {
    code: ?i32,              // HTTP 状态码或自定义错误码
    message: []const u8,     // 错误消息
    location: ?[]const u8,   // 源码位置 (@src().file)
    details: ?[]const u8,    // 详细信息（如响应体）
    timestamp: i64,          // Unix 毫秒时间戳
};
```

**设计决策**:
- 使用可选类型 `?T` 支持部分信息缺失
- `message` 必填，其他字段可选
- `timestamp` 使用 i64 毫秒时间戳
- 字符串使用切片 `[]const u8`，不持有内存

---

### WrappedError

```zig
pub const WrappedError = struct {
    error_type: anyerror,        // 原始错误类型
    context: ErrorContext,       // 错误上下文
    source: ?*WrappedError,      // 源错误（形成链表）

    pub fn unwind(self: *const WrappedError, allocator: Allocator) ![]ErrorContext {
        var contexts = std.ArrayList(ErrorContext).init(allocator);
        var current: ?*const WrappedError = self;

        while (current) |err| {
            try contexts.append(err.context);
            current = err.source;
        }

        return contexts.toOwnedSlice();
    }
};
```

**设计决策**:
- 使用链表结构表示错误链
- `anyerror` 类型支持任意 Zig 错误
- `unwind()` 方法展开完整错误链

---

### 错误分类

```zig
// 网络相关错误
pub const NetworkError = error{
    ConnectionFailed,      // 连接失败
    Timeout,              // 超时
    DNSResolutionFailed,  // DNS 解析失败
    SSLError,             // SSL/TLS 错误
};

// API 相关错误
pub const APIError = error{
    Unauthorized,         // 未授权（401）
    RateLimitExceeded,    // 限流（429）
    InvalidRequest,       // 无效请求（400）
    ServerError,          // 服务器错误（500）
};

// 数据相关错误
pub const DataError = error{
    InvalidFormat,        // 格式错误
    ParseError,           // 解析失败
    ValidationFailed,     // 验证失败
    MissingField,         // 缺少字段
};

// 业务相关错误
pub const BusinessError = error{
    InsufficientBalance,  // 余额不足
    OrderNotFound,        // 订单不存在
    InvalidOrderStatus,   // 订单状态无效
    PositionNotFound,     // 持仓不存在
};

// 系统相关错误
pub const SystemError = error{
    OutOfMemory,          // 内存不足
    FileNotFound,         // 文件不存在
    PermissionDenied,     // 权限拒绝
    ResourceExhausted,    // 资源耗尽
};

// 组合错误集
pub const Error = NetworkError || APIError || DataError || BusinessError || SystemError;
```

**设计决策**:
- 按功能域分类，便于管理
- 使用 `||` 组合多个错误集
- 每个错误都有明确的语义

---

## 核心算法

### 1. 错误包装

```zig
pub fn wrap(
    err: anyerror,
    message: []const u8,
    extra: anytype,
) WrappedError {
    const ctx = ErrorContext{
        .code = if (@hasField(@TypeOf(extra), "code")) extra.code else null,
        .message = message,
        .location = if (@hasField(@TypeOf(extra), "location")) extra.location else null,
        .details = if (@hasField(@TypeOf(extra), "details")) extra.details else null,
        .timestamp = std.time.timestamp() * 1000,
    };

    return WrappedError{
        .error_type = err,
        .context = ctx,
        .source = null,  // 需要手动设置源错误
    };
}

pub fn wrapWithSource(
    err: anyerror,
    message: []const u8,
    source: *WrappedError,
    extra: anytype,
) WrappedError {
    var wrapped = wrap(err, message, extra);
    wrapped.source = source;
    return wrapped;
}
```

**算法说明**:
1. 使用 `@hasField` 检查额外字段是否存在
2. 自动添加时间戳
3. 支持链接源错误

---

### 2. 重试机制

```zig
pub const RetryStrategy = enum {
    fixed_interval,        // 固定间隔
    exponential_backoff,   // 指数退避
};

pub const RetryConfig = struct {
    max_retries: u32,          // 最大重试次数
    strategy: RetryStrategy,   // 重试策略
    initial_delay_ms: u64,     // 初始延迟（毫秒）
    max_delay_ms: u64,         // 最大延迟（毫秒）
};

pub fn retry(
    config: RetryConfig,
    comptime func: anytype,
    args: anytype,
) !@typeInfo(@TypeOf(func)).Fn.return_type.? {
    const ReturnType = @typeInfo(@TypeOf(func)).Fn.return_type.?;

    var attempt: u32 = 0;
    var delay_ms = config.initial_delay_ms;

    while (attempt <= config.max_retries) : (attempt += 1) {
        if (attempt > 0) {
            // 延迟
            std.time.sleep(delay_ms * std.time.ns_per_ms);

            // 更新延迟
            switch (config.strategy) {
                .fixed_interval => {}, // 保持不变
                .exponential_backoff => {
                    delay_ms = @min(delay_ms * 2, config.max_delay_ms);
                },
            }
        }

        // 调用函数
        if (@call(.auto, func, args)) |result| {
            return result;
        } else |err| {
            if (attempt == config.max_retries) {
                return err;  // 最后一次重试失败
            }
            // 继续重试
        }
    }

    unreachable;
}
```

**算法说明**:
1. **固定间隔**: 每次重试延迟相同
2. **指数退避**: 延迟翻倍，直到达到最大值
3. 使用 `@call` 动态调用函数
4. 最后一次失败返回错误

**示例**:
```
attempt=0: 立即执行
attempt=1: 延迟 1000ms
attempt=2: 延迟 2000ms
attempt=3: 延迟 4000ms
attempt=4: 延迟 8000ms (达到 max_delay_ms)
```

---

### 3. 错误判断

```zig
pub fn isRetriable(err: anyerror) bool {
    return switch (err) {
        // 可重试的网络错误
        NetworkError.Timeout,
        NetworkError.ConnectionFailed,
        // 可重试的 API 错误
        APIError.RateLimitExceeded,
        APIError.ServerError,
        => true,
        // 其他错误不重试
        else => false,
    };
}

pub fn isTemporary(err: anyerror) bool {
    return switch (err) {
        NetworkError.Timeout,
        APIError.RateLimitExceeded,
        SystemError.ResourceExhausted,
        => true,
        else => false,
    };
}
```

**设计决策**:
- `isRetriable()`: 是否应该重试
- `isTemporary()`: 是否是临时错误
- 业务错误通常不可重试

---

## 错误处理模式

### 1. 立即返回

```zig
pub fn fetchData(url: []const u8) ![]const u8 {
    const response = try http.get(url);
    if (response.status_code != 200) {
        return APIError.ServerError;
    }
    return response.body;
}
```

### 2. 捕获并转换

```zig
pub fn parseJSON(data: []const u8) !Order {
    const order = json.parse(data) catch |err| {
        return DataError.ParseError;  // 转换为业务错误
    };
    return order;
}
```

### 3. 捕获并包装

```zig
pub fn processOrder(order_id: []const u8) !void {
    const order = fetchOrder(order_id) catch |err| {
        return wrap(err, "Failed to fetch order", .{
            .order_id = order_id,
        });
    };
    // ...
}
```

### 4. 带重试

```zig
pub fn fetchDataWithRetry(url: []const u8) ![]const u8 {
    const config = RetryConfig{
        .max_retries = 3,
        .strategy = .exponential_backoff,
        .initial_delay_ms = 1000,
        .max_delay_ms = 10000,
    };

    return retry(config, fetchData, .{url});
}
```

---

## 内存管理

### 栈分配

```zig
// ErrorContext 通常在栈上分配
const ctx = ErrorContext{
    .code = 429,
    .message = "Rate limit exceeded",
    .location = @src().file,
    .details = null,
    .timestamp = std.time.timestamp(),
};
```

### 堆分配（错误链）

```zig
// WrappedError 包含指针，需要堆分配
var wrapped = try allocator.create(WrappedError);
wrapped.* = wrap(err, "Error message", .{});
defer allocator.destroy(wrapped);
```

---

## 线程安全

- `ErrorContext` 是不可变值类型，线程安全
- `WrappedError` 包含指针，需要同步访问
- 重试机制不保证线程安全（使用锁保护共享状态）

---

## 性能优化

### 1. 避免不必要的包装

```zig
// ✅ 直接返回
return APIError.RateLimitExceeded;

// ❌ 不必要的包装
return wrap(APIError.RateLimitExceeded, "Rate limit", .{});
```

### 2. 使用编译时类型检查

```zig
comptime {
    // 确保 func 是函数类型
    if (@typeInfo(@TypeOf(func)) != .Fn) {
        @compileError("Expected function type");
    }
}
```

### 3. 内联小函数

```zig
pub inline fn isRetriable(err: anyerror) bool {
    // 编译器会内联此函数
    return switch (err) { ... };
}
```

---

## 测试覆盖

详见 [testing.md](./testing.md)

- 单元测试: 所有错误类型
- 集成测试: 错误包装、重试机制
- 边界测试: 最大重试次数、错误链深度

---

*Last updated: 2025-01-22*
