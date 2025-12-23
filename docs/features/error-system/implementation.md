# Error System - 实现细节

> 内部实现说明和设计决策

**最后更新**: 2025-12-23

---

## 核心数据结构

### ErrorContext

```zig
pub const ErrorContext = struct {
    code: ?i32,              // HTTP 状态码或自定义错误码
    message: []const u8,     // 错误消息
    location: ?[]const u8,   // 源码位置 (@src().file)
    details: ?[]const u8,    // 详细信息（如响应体）
    timestamp: i64,          // Unix 秒时间戳
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
    error_type: anyerror,          // 原始错误类型
    context: ErrorContext,         // 错误上下文
    source: ?*const WrappedError,  // 源错误（形成链表）

    pub fn chainDepth(self: *const WrappedError) usize {
        var depth: usize = 1;
        var current = self.source;
        while (current) |src| {
            depth += 1;
            current = src.source;
        }
        return depth;
    }

    pub fn printChain(self: *const WrappedError, writer: anytype) !void {
        try writer.print("Error chain:\n", .{});
        try writer.print("  [0] {s}: {f}\n", .{ @errorName(self.error_type), self.context });

        var depth: usize = 1;
        var current = self.source;
        while (current) |src| {
            try writer.print("  [{d}] {s}: {f}\n", .{ depth, @errorName(src.error_type), src.context });
            depth += 1;
            current = src.source;
        }
    }
};
```

**设计决策**:
- 使用链表结构表示错误链
- `anyerror` 类型支持任意 Zig 错误
- `chainDepth()` 遍历链表计算深度
- `printChain()` 格式化输出完整错误链
- ErrorContext 的 `format()` 方法通过 `{f}` 调用

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
    BadRequest,           // 错误请求（400）
    NotFound,             // 未找到（404）
};

// 数据相关错误
pub const DataError = error{
    InvalidFormat,        // 格式错误
    ParseError,           // 解析失败
    ValidationFailed,     // 验证失败
    MissingField,         // 缺少字段
    TypeMismatch,         // 类型不匹配
};

// 业务相关错误
pub const BusinessError = error{
    InsufficientBalance,  // 余额不足
    OrderNotFound,        // 订单不存在
    InvalidOrderStatus,   // 订单状态无效
    PositionNotFound,     // 持仓不存在
    InvalidQuantity,      // 数量无效
    MarketClosed,         // 市场关闭
};

// 系统相关错误
pub const SystemError = error{
    OutOfMemory,          // 内存不足
    FileNotFound,         // 文件不存在
    PermissionDenied,     // 权限拒绝
    ResourceExhausted,    // 资源耗尽
};

// 组合错误集
pub const TradingError = NetworkError || APIError || DataError || BusinessError || SystemError;
```

**设计决策**:
- 按功能域分类，便于管理
- 使用 `||` 组合多个错误集
- 每个错误都有明确的语义

---

## 核心算法

### 1. 错误包装

```zig
/// 简单包装错误
pub fn wrap(err: anyerror, message: []const u8) WrappedError {
    return WrappedError.init(err, ErrorContext.init(message));
}

/// 包装错误并添加错误码
pub fn wrapWithCode(err: anyerror, code: i32, message: []const u8) WrappedError {
    return WrappedError.init(err, ErrorContext.initWithCode(code, message));
}

/// 包装错误并链接源错误
pub fn wrapWithSource(err: anyerror, message: []const u8, source: *const WrappedError) WrappedError {
    return WrappedError.initWithSource(err, ErrorContext.init(message), source);
}
```

**算法说明**:
1. `ErrorContext.init()` 自动添加当前时间戳
2. `ErrorContext.initWithCode()` 添加错误码和时间戳
3. `WrappedError.initWithSource()` 创建错误链

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
) @TypeOf(@call(.auto, func, args)) {
    var attempt: u32 = 0;

    while (attempt <= config.max_retries) : (attempt += 1) {
        // 尝试执行函数
        if (@call(.auto, func, args)) |result| {
            return result;
        } else |err| {
            // 如果是最后一次尝试，返回错误
            if (attempt >= config.max_retries) {
                return err;
            }

            // 计算延迟并等待
            const delay_ms = config.calculateDelay(attempt);
            std.Thread.sleep(delay_ms * std.time.ns_per_ms);
        }
    }

    unreachable;
}
```

**算法说明**:
1. 使用 `@call(.auto, func, args)` 动态调用函数
2. 使用 `config.calculateDelay(attempt)` 计算延迟时间
3. 使用 `std.Thread.sleep()` 进行等待
4. 最后一次失败返回错误
5. 返回类型通过 `@TypeOf(@call(...))` 自动推导

**RetryConfig.calculateDelay() 实现**:
```zig
pub fn calculateDelay(self: RetryConfig, attempt: u32) u64 {
    return switch (self.strategy) {
        .fixed_interval => self.initial_delay_ms,
        .exponential_backoff => blk: {
            const multiplier = std.math.pow(u64, 2, attempt);
            const delay = self.initial_delay_ms * multiplier;
            break :blk @min(delay, self.max_delay_ms);
        },
    };
}
```

**示例** (exponential_backoff, initial=1000ms, max=10000ms):
```
attempt=0: 1000ms (1000 * 2^0)
attempt=1: 2000ms (1000 * 2^1)
attempt=2: 4000ms (1000 * 2^2)
attempt=3: 8000ms (1000 * 2^3)
attempt=4: 10000ms (达到 max_delay_ms)
```

---

### 3. 错误判断

```zig
pub fn isRetryable(err: anyerror) bool {
    return switch (err) {
        // 网络错误是可重试的
        NetworkError.ConnectionFailed,
        NetworkError.Timeout,
        NetworkError.DNSResolutionFailed,

        // 部分 API 错误可重试
        APIError.RateLimitExceeded,
        APIError.ServerError,

        // 系统资源错误可重试
        SystemError.ResourceExhausted,

        => true,

        // 其他错误不重试
        else => false,
    };
}

pub fn errorCategory(err: anyerror) []const u8 {
    // 检查每个错误集
    inline for (@typeInfo(NetworkError).error_set.?) |e| {
        if (err == @field(NetworkError, e.name)) return "Network";
    }
    inline for (@typeInfo(APIError).error_set.?) |e| {
        if (err == @field(APIError, e.name)) return "API";
    }
    inline for (@typeInfo(DataError).error_set.?) |e| {
        if (err == @field(DataError, e.name)) return "Data";
    }
    inline for (@typeInfo(BusinessError).error_set.?) |e| {
        if (err == @field(BusinessError, e.name)) return "Business";
    }
    inline for (@typeInfo(SystemError).error_set.?) |e| {
        if (err == @field(SystemError, e.name)) return "System";
    }

    return "Unknown";
}
```

**设计决策**:
- `isRetryable()`: 判断是否应该重试（网络、部分API、系统资源错误）
- `errorCategory()`: 使用编译时反射获取错误类别
- 业务错误（BusinessError）和数据错误（DataError）通常不可重试

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
        return wrap(err, "Failed to fetch order");
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
return wrap(APIError.RateLimitExceeded, "Rate limit");
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

*Last updated: 2025-12-23*
