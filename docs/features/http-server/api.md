# HTTP Server - API 参考

> 完整的 API 文档

**最后更新**: 2025-12-28

---

## 类型定义

### ApiServer

```zig
pub const ApiServer = struct {
    allocator: Allocator,
    server: httpz.Server(.{}),
    config: ApiConfig,
    jwt_manager: JwtManager,
    metrics_collector: MetricsCollector,
    strategy_registry: *StrategyRegistry,
    backtest_engine: *BacktestEngine,
    trading_engine: ?*LiveTradingEngine,
    running: std.atomic.Value(bool),
    start_time: i64,
};
```

### ApiConfig

```zig
pub const ApiConfig = struct {
    /// 监听地址
    host: []const u8 = "0.0.0.0",

    /// 监听端口
    port: u16 = 8080,

    /// 工作线程数
    workers: u16 = 4,

    /// JWT 签名密钥 (至少 32 字节)
    jwt_secret: []const u8,

    /// JWT 过期时间 (小时)
    jwt_expiry_hours: u32 = 24,

    /// CORS 允许的源
    cors_origins: []const []const u8 = &.{"*"},

    /// 读取超时 (毫秒)
    read_timeout_ms: u32 = 30000,

    /// 写入超时 (毫秒)
    write_timeout_ms: u32 = 30000,
};
```

### Dependencies

```zig
pub const Dependencies = struct {
    strategy_registry: *StrategyRegistry,
    backtest_engine: *BacktestEngine,
    trading_engine: ?*LiveTradingEngine = null,
};
```

### JwtManager

```zig
pub const JwtManager = struct {
    allocator: Allocator,
    secret: []const u8,
    expiry_hours: u32,
};
```

### JwtPayload

```zig
pub const JwtPayload = struct {
    /// 用户 ID
    sub: []const u8,

    /// 签发时间 (Unix timestamp)
    iat: i64,

    /// 过期时间 (Unix timestamp)
    exp: i64,
};
```

### RequestContext

```zig
pub const RequestContext = struct {
    server: *ApiServer,
    allocator: Allocator,
    user_id: ?[]const u8,
    request_id: [36]u8,
    start_time: i64,
};
```

---

## ApiServer 函数

### `init`

```zig
pub fn init(allocator: Allocator, config: ApiConfig, deps: Dependencies) !*ApiServer
```

**描述**: 创建并初始化 API 服务器

**参数**:
- `allocator`: 内存分配器
- `config`: 服务器配置
- `deps`: 依赖的服务实例

**返回**: 指向 ApiServer 的指针

**错误**:
- `error.OutOfMemory`: 内存分配失败
- `error.AddressInUse`: 端口已被占用

**示例**:
```zig
var server = try ApiServer.init(allocator, .{
    .port = 8080,
    .jwt_secret = secret,
}, .{
    .strategy_registry = &registry,
    .backtest_engine = &engine,
});
defer server.deinit();
```

---

### `start`

```zig
pub fn start(self: *ApiServer) !void
```

**描述**: 启动 HTTP 服务器，开始监听请求

**参数**:
- `self`: ApiServer 实例

**返回**: void

**错误**:
- `error.AlreadyRunning`: 服务器已在运行
- `error.BindError`: 无法绑定端口

**示例**:
```zig
try server.start();
// 服务器开始监听...
```

---

### `stop`

```zig
pub fn stop(self: *ApiServer) void
```

**描述**: 优雅停止服务器，等待当前请求完成

**参数**:
- `self`: ApiServer 实例

**示例**:
```zig
server.stop();
// 服务器已停止
```

---

### `deinit`

```zig
pub fn deinit(self: *ApiServer) void
```

**描述**: 释放服务器资源

**参数**:
- `self`: ApiServer 实例

**示例**:
```zig
defer server.deinit();
```

---

## JwtManager 函数

### `init`

```zig
pub fn init(allocator: Allocator, secret: []const u8, expiry_hours: u32) JwtManager
```

**描述**: 创建 JWT 管理器

**参数**:
- `allocator`: 内存分配器
- `secret`: 签名密钥 (至少 32 字节)
- `expiry_hours`: Token 过期时间 (小时)

**返回**: JwtManager 实例

**示例**:
```zig
const jwt = JwtManager.init(allocator, "your-secret-key-at-least-32-bytes", 24);
```

---

### `generateToken`

```zig
pub fn generateToken(self: *JwtManager, user_id: []const u8) ![]const u8
```

**描述**: 生成 JWT Token

**参数**:
- `self`: JwtManager 实例
- `user_id`: 用户 ID

**返回**: JWT Token 字符串 (调用者负责释放)

**错误**:
- `error.OutOfMemory`: 内存分配失败

**示例**:
```zig
const token = try jwt.generateToken("user_123");
defer allocator.free(token);
```

---

### `verifyToken`

```zig
pub fn verifyToken(self: *JwtManager, token: []const u8) !JwtPayload
```

**描述**: 验证 JWT Token

**参数**:
- `self`: JwtManager 实例
- `token`: JWT Token 字符串

**返回**: JwtPayload 包含用户信息

**错误**:
- `error.InvalidToken`: Token 格式无效
- `error.InvalidSignature`: 签名验证失败
- `error.TokenExpired`: Token 已过期

**示例**:
```zig
const payload = try jwt.verifyToken(token);
std.debug.print("User: {s}\n", .{payload.sub});
```

---

## RequestContext 函数

### `init`

```zig
pub fn init(server: *ApiServer, allocator: Allocator) RequestContext
```

**描述**: 创建请求上下文

**参数**:
- `server`: ApiServer 实例
- `allocator`: 请求级分配器

**返回**: RequestContext 实例

---

### `isAuthenticated`

```zig
pub fn isAuthenticated(self: *const RequestContext) bool
```

**描述**: 检查请求是否已认证

**返回**: 是否已认证

---

## 中间件

### Logger 中间件

```zig
pub fn loggerMiddleware(
    ctx: *RequestContext,
    req: *httpz.Request,
    res: *httpz.Response,
) !void
```

**描述**: 记录请求日志和指标

**日志格式**:
```
[request_id] METHOD /path STATUS duration_ms
```

---

### CORS 中间件

```zig
pub fn corsMiddleware(
    allowed_origins: []const []const u8,
) httpz.Middleware(RequestContext)
```

**描述**: 处理跨域请求

**参数**:
- `allowed_origins`: 允许的源列表，`["*"]` 表示允许所有

**添加的响应头**:
- `Access-Control-Allow-Origin`
- `Access-Control-Allow-Methods`
- `Access-Control-Allow-Headers`
- `Access-Control-Max-Age`

---

### Auth 中间件

```zig
pub fn authMiddleware(
    ctx: *RequestContext,
    req: *httpz.Request,
    res: *httpz.Response,
) !void
```

**描述**: JWT Token 认证

**期望的请求头**:
```
Authorization: Bearer <token>
```

**错误响应**:
- 401: 缺少 Authorization 头
- 401: 无效的 Authorization 格式
- 401: Token 过期或无效

---

## 完整示例

### 基本服务器

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建依赖
    var registry = try zigQuant.StrategyRegistry.init(allocator);
    defer registry.deinit();

    var engine = try zigQuant.BacktestEngine.init(allocator, .{});
    defer engine.deinit();

    // 从环境变量读取配置
    const secret = std.posix.getenv("JWT_SECRET") orelse "default-dev-secret-32-bytes!!!!!";

    // 创建服务器
    var server = try zigQuant.ApiServer.init(allocator, .{
        .port = 8080,
        .jwt_secret = secret,
        .jwt_expiry_hours = 24,
        .cors_origins = &.{"http://localhost:3000"},
    }, .{
        .strategy_registry = &registry,
        .backtest_engine = &engine,
    });
    defer server.deinit();

    // 启动服务器
    std.log.info("Starting server on http://0.0.0.0:8080", .{});
    try server.start();
}
```

### 使用 JwtManager

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var jwt = zigQuant.JwtManager.init(
        allocator,
        "my-super-secret-key-at-least-32-bytes",
        24,
    );

    // 生成 Token
    const token = try jwt.generateToken("user_123");
    defer allocator.free(token);
    std.debug.print("Token: {s}\n", .{token});

    // 验证 Token
    const payload = try jwt.verifyToken(token);
    std.debug.print("User ID: {s}\n", .{payload.sub});
    std.debug.print("Issued at: {d}\n", .{payload.iat});
    std.debug.print("Expires at: {d}\n", .{payload.exp});
}
```

---

*Last updated: 2025-12-28*
