# Error System - API 参考

> 完整的 API 文档和使用示例

**最后更新**: 2025-01-22

---

## 错误类型

### NetworkError

网络相关错误

```zig
pub const NetworkError = error{
    ConnectionFailed,      // 连接失败
    Timeout,              // 超时
    DNSResolutionFailed,  // DNS 解析失败
    SSLError,             // SSL/TLS 错误
};
```

**使用示例**:

```zig
pub fn connectToServer(host: []const u8, port: u16) !Socket {
    const socket = Socket.connect(host, port) catch {
        return NetworkError.ConnectionFailed;
    };
    return socket;
}
```

---

### APIError

API 调用相关错误

```zig
pub const APIError = error{
    Unauthorized,         // 未授权（401）
    RateLimitExceeded,    // 限流（429）
    InvalidRequest,       // 无效请求（400）
    ServerError,          // 服务器错误（500）
};
```

**使用示例**:

```zig
pub fn callAPI(endpoint: []const u8) !Response {
    const response = try http.get(endpoint);

    return switch (response.status_code) {
        200 => response,
        401 => APIError.Unauthorized,
        429 => APIError.RateLimitExceeded,
        400 => APIError.InvalidRequest,
        500 => APIError.ServerError,
        else => APIError.ServerError,
    };
}
```

---

### DataError

数据处理相关错误

```zig
pub const DataError = error{
    InvalidFormat,        // 格式错误
    ParseError,           // 解析失败
    ValidationFailed,     // 验证失败
    MissingField,         // 缺少字段
};
```

**使用示例**:

```zig
pub fn parseOrder(data: []const u8) !Order {
    const json_value = json.parse(data) catch {
        return DataError.ParseError;
    };

    const order_id = json_value.get("order_id") orelse {
        return DataError.MissingField;
    };

    if (!validateOrderId(order_id)) {
        return DataError.ValidationFailed;
    }

    return Order{ .id = order_id };
}
```

---

### BusinessError

业务逻辑相关错误

```zig
pub const BusinessError = error{
    InsufficientBalance,  // 余额不足
    OrderNotFound,        // 订单不存在
    InvalidOrderStatus,   // 订单状态无效
    PositionNotFound,     // 持仓不存在
};
```

**使用示例**:

```zig
pub fn createOrder(account: *Account, amount: Decimal) !Order {
    if (account.balance.cmp(amount) == .lt) {
        return BusinessError.InsufficientBalance;
    }

    // 创建订单...
}

pub fn cancelOrder(order_id: []const u8) !void {
    const order = findOrder(order_id) orelse {
        return BusinessError.OrderNotFound;
    };

    if (order.status != .open) {
        return BusinessError.InvalidOrderStatus;
    }

    // 取消订单...
}
```

---

### SystemError

系统资源相关错误

```zig
pub const SystemError = error{
    OutOfMemory,          // 内存不足
    FileNotFound,         // 文件不存在
    PermissionDenied,     // 权限拒绝
    ResourceExhausted,    // 资源耗尽
};
```

**使用示例**:

```zig
pub fn allocateBuffer(size: usize) ![]u8 {
    const buffer = allocator.alloc(u8, size) catch {
        return SystemError.OutOfMemory;
    };
    return buffer;
}

pub fn openFile(path: []const u8) !File {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => SystemError.FileNotFound,
            error.AccessDenied => SystemError.PermissionDenied,
            else => err,
        };
    };
    return file;
}
```

---

## ErrorContext

错误上下文信息

```zig
pub const ErrorContext = struct {
    code: ?i32,              // 错误码（如 HTTP 状态码）
    message: []const u8,     // 错误消息
    location: ?[]const u8,   // 源码位置
    details: ?[]const u8,    // 详细信息
    timestamp: i64,          // Unix 毫秒时间戳
};
```

### 构造

```zig
const ctx = ErrorContext{
    .code = 429,
    .message = "Rate limit exceeded",
    .location = @src().file,
    .details = "Retry after 60 seconds",
    .timestamp = std.time.timestamp() * 1000,
};
```

### 使用场景

```zig
pub fn logError(ctx: ErrorContext) void {
    logger.error("{s} [code={}] at {s}: {s}", .{
        ctx.message,
        ctx.code orelse 0,
        ctx.location orelse "unknown",
        ctx.details orelse "",
    });
}
```

---

## WrappedError

包装错误（支持错误链）

```zig
pub const WrappedError = struct {
    error_type: anyerror,        // 原始错误类型
    context: ErrorContext,       // 错误上下文
    source: ?*WrappedError,      // 源错误

    pub fn unwind(self: *const WrappedError, allocator: Allocator) ![]ErrorContext;
};
```

### 方法

#### `unwind(allocator: Allocator) ![]ErrorContext`

展开错误链，返回所有上下文

```zig
const contexts = try wrapped_error.unwind(allocator);
defer allocator.free(contexts);

for (contexts) |ctx| {
    std.debug.print("{s}\n", .{ctx.message});
}
```

---

## wrap()

包装错误

```zig
pub fn wrap(
    err: anyerror,
    message: []const u8,
    extra: anytype,
) WrappedError
```

**参数**:
- `err`: 原始错误
- `message`: 错误消息
- `extra`: 额外字段（可选）

**返回**: WrappedError

**示例**:

```zig
pub fn fetchOrder(order_id: []const u8) !Order {
    const data = fetchData(order_id) catch |err| {
        return wrap(err, "Failed to fetch order", .{
            .code = null,
            .location = @src().file,
            .details = order_id,
        });
    };

    return parseOrder(data);
}
```

---

## wrapWithSource()

包装错误并设置源错误

```zig
pub fn wrapWithSource(
    err: anyerror,
    message: []const u8,
    source: *WrappedError,
    extra: anytype,
) WrappedError
```

**参数**:
- `err`: 原始错误
- `message`: 错误消息
- `source`: 源错误
- `extra`: 额外字段

**示例**:

```zig
var source = wrap(NetworkError.Timeout, "Network timeout", .{});
const wrapped = wrapWithSource(
    APIError.ServerError,
    "API call failed",
    &source,
    .{},
);
```

---

## RetryConfig

重试配置

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
```

### 预定义配置

```zig
pub const DEFAULT_RETRY = RetryConfig{
    .max_retries = 3,
    .strategy = .exponential_backoff,
    .initial_delay_ms = 1000,
    .max_delay_ms = 10000,
};

pub const AGGRESSIVE_RETRY = RetryConfig{
    .max_retries = 5,
    .strategy = .exponential_backoff,
    .initial_delay_ms = 500,
    .max_delay_ms = 5000,
};
```

---

## retry()

执行重试

```zig
pub fn retry(
    config: RetryConfig,
    comptime func: anytype,
    args: anytype,
) !@TypeOf(func).ReturnType
```

**参数**:
- `config`: 重试配置
- `func`: 要重试的函数
- `args`: 函数参数

**返回**: 函数返回值

**错误**: 最后一次重试失败返回错误

**示例**:

```zig
const config = RetryConfig{
    .max_retries = 3,
    .strategy = .exponential_backoff,
    .initial_delay_ms = 1000,
    .max_delay_ms = 10000,
};

const data = try retry(config, fetchData, .{"https://api.example.com"});
```

---

## isRetriable()

判断错误是否可重试

```zig
pub fn isRetriable(err: anyerror) bool
```

**参数**:
- `err`: 错误

**返回**: 可重试返回 `true`

**示例**:

```zig
const err = APIError.RateLimitExceeded;
if (isRetriable(err)) {
    // 可以重试
    const result = try retry(DEFAULT_RETRY, fetchData, .{url});
}
```

**可重试的错误**:
- `NetworkError.Timeout`
- `NetworkError.ConnectionFailed`
- `APIError.RateLimitExceeded`
- `APIError.ServerError`

---

## isTemporary()

判断错误是否是临时错误

```zig
pub fn isTemporary(err: anyerror) bool
```

**参数**:
- `err`: 错误

**返回**: 临时错误返回 `true`

**示例**:

```zig
fetchData(url) catch |err| {
    if (isTemporary(err)) {
        std.log.warn("Temporary error, will retry: {}", .{err});
    } else {
        std.log.err("Permanent error: {}", .{err});
        return err;
    }
};
```

---

## 完整示例

### 示例 1: 带重试的 API 调用

```zig
const std = @import("std");
const errors = @import("core/errors.zig");

pub fn fetchMarketData(symbol: []const u8) ![]const u8 {
    const config = errors.RetryConfig{
        .max_retries = 3,
        .strategy = .exponential_backoff,
        .initial_delay_ms = 1000,
        .max_delay_ms = 10000,
    };

    return errors.retry(config, fetchMarketDataOnce, .{symbol});
}

fn fetchMarketDataOnce(symbol: []const u8) ![]const u8 {
    const url = try std.fmt.allocPrint(
        allocator,
        "https://api.example.com/market/{s}",
        .{symbol},
    );
    defer allocator.free(url);

    const response = http.get(url) catch {
        return errors.NetworkError.ConnectionFailed;
    };

    if (response.status_code == 429) {
        return errors.APIError.RateLimitExceeded;
    }

    if (response.status_code != 200) {
        return errors.APIError.ServerError;
    }

    return response.body;
}
```

### 示例 2: 错误包装和日志

```zig
pub fn processOrder(order_id: []const u8) !void {
    const order = fetchOrder(order_id) catch |err| {
        const ctx = errors.ErrorContext{
            .code = null,
            .message = "Failed to fetch order",
            .location = @src().file,
            .details = order_id,
            .timestamp = std.time.timestamp() * 1000,
        };
        logger.logError(ctx);
        return err;
    };

    executeOrder(order) catch |err| {
        const ctx = errors.ErrorContext{
            .code = null,
            .message = "Failed to execute order",
            .location = @src().file,
            .details = order.id,
            .timestamp = std.time.timestamp() * 1000,
        };
        logger.logError(ctx);
        return err;
    };
}
```

---

*Last updated: 2025-01-22*
