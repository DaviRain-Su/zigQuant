# HTTP Server - 实现细节

> 深入了解内部实现

**最后更新**: 2025-12-28

---

## 架构概述

```
┌─────────────────────────────────────────────────────────┐
│                     ApiServer                            │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │   http.zig      │  │      Middleware Chain       │  │
│  │   Server        │──│  Logger → CORS → Auth       │  │
│  └─────────────────┘  └─────────────────────────────┘  │
│           │                        │                     │
│           ▼                        ▼                     │
│  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │     Router      │  │        Handlers             │  │
│  │                 │──│  health, strategies, ...    │  │
│  └─────────────────┘  └─────────────────────────────┘  │
│           │                        │                     │
│           ▼                        ▼                     │
│  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │   JwtManager    │  │    MetricsCollector         │  │
│  └─────────────────┘  └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## 内部表示

### ApiServer 数据结构

```zig
pub const ApiServer = struct {
    allocator: Allocator,
    server: httpz.Server(.{}),
    config: ApiConfig,
    jwt_manager: JwtManager,
    metrics_collector: MetricsCollector,

    // 依赖注入的服务
    strategy_registry: *StrategyRegistry,
    backtest_engine: *BacktestEngine,
    trading_engine: ?*LiveTradingEngine,

    // 运行状态
    running: std.atomic.Value(bool),
    start_time: i64,

    const Self = @This();

    pub fn init(allocator: Allocator, config: ApiConfig, deps: Dependencies) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // 初始化 http.zig 服务器
        var server = try httpz.Server(.{}).init(allocator, .{
            .port = config.port,
            .address = config.host,
            .num_workers = config.workers,
        });

        self.* = .{
            .allocator = allocator,
            .server = server,
            .config = config,
            .jwt_manager = JwtManager.init(allocator, config.jwt_secret, config.jwt_expiry_hours),
            .metrics_collector = MetricsCollector.init(allocator),
            .strategy_registry = deps.strategy_registry,
            .backtest_engine = deps.backtest_engine,
            .trading_engine = deps.trading_engine,
            .running = std.atomic.Value(bool).init(false),
            .start_time = 0,
        };

        // 配置中间件
        self.setupMiddleware();

        // 配置路由
        self.setupRoutes();

        return self;
    }
};
```

### 请求上下文

```zig
pub const RequestContext = struct {
    server: *ApiServer,
    allocator: Allocator,
    user_id: ?[]const u8,
    request_id: [36]u8,
    start_time: i64,

    pub fn init(server: *ApiServer, allocator: Allocator) RequestContext {
        return .{
            .server = server,
            .allocator = allocator,
            .user_id = null,
            .request_id = generateUuid(),
            .start_time = std.time.nanoTimestamp(),
        };
    }

    pub fn isAuthenticated(self: *const RequestContext) bool {
        return self.user_id != null;
    }
};
```

---

## 核心算法

### JWT Token 生成

```zig
pub fn generateToken(self: *JwtManager, user_id: []const u8) ![]const u8 {
    const now = std.time.timestamp();
    const exp = now + @as(i64, self.expiry_hours) * 3600;

    // 1. 构建 Header (固定)
    const header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9";

    // 2. 构建 Payload
    const payload_json = try std.fmt.allocPrint(self.allocator,
        \\{{"sub":"{s}","iat":{d},"exp":{d}}}
    , .{user_id, now, exp});
    defer self.allocator.free(payload_json);

    const payload = try base64UrlEncode(self.allocator, payload_json);
    defer self.allocator.free(payload);

    // 3. 计算签名
    const message = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{header, payload});
    defer self.allocator.free(message);

    var hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(self.secret);
    hmac.update(message);
    var signature: [32]u8 = undefined;
    hmac.final(&signature);

    const sig_b64 = try base64UrlEncode(self.allocator, &signature);
    defer self.allocator.free(sig_b64);

    // 4. 组合 Token
    return try std.fmt.allocPrint(self.allocator, "{s}.{s}.{s}",
        .{header, payload, sig_b64});
}
```

**复杂度**: O(n) 其中 n 是 payload 长度
**说明**: 使用 HMAC-SHA256 签名，确保 Token 完整性

### JWT Token 验证

```zig
pub fn verifyToken(self: *JwtManager, token: []const u8) !JwtPayload {
    // 1. 分割 Token
    var parts = std.mem.splitScalar(u8, token, '.');
    const header_b64 = parts.next() orelse return error.InvalidToken;
    const payload_b64 = parts.next() orelse return error.InvalidToken;
    const sig_b64 = parts.next() orelse return error.InvalidToken;

    // 2. 验证签名
    const message = try std.fmt.allocPrint(self.allocator, "{s}.{s}",
        .{header_b64, payload_b64});
    defer self.allocator.free(message);

    var hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(self.secret);
    hmac.update(message);
    var expected_sig: [32]u8 = undefined;
    hmac.final(&expected_sig);

    const actual_sig = try base64UrlDecode(self.allocator, sig_b64);
    defer self.allocator.free(actual_sig);

    if (!std.crypto.utils.timingSafeEql([32]u8, expected_sig, actual_sig[0..32].*)) {
        return error.InvalidSignature;
    }

    // 3. 解析 Payload
    const payload_json = try base64UrlDecode(self.allocator, payload_b64);
    defer self.allocator.free(payload_json);

    const parsed = try std.json.parseFromSlice(JwtPayload, self.allocator, payload_json, .{});
    defer parsed.deinit();

    // 4. 验证过期时间
    if (parsed.value.exp < std.time.timestamp()) {
        return error.TokenExpired;
    }

    return parsed.value;
}
```

**复杂度**: O(n)
**说明**: 使用时序安全比较防止时序攻击

### 路由匹配

```zig
fn setupRoutes(self: *Self) void {
    const router = self.server.router();

    // 公开路由 (无认证)
    router.get("/health", handlers.health.get);
    router.get("/ready", handlers.health.ready);
    router.get("/metrics", handlers.metrics.prometheus);
    router.post("/api/v1/auth/login", handlers.auth.login);

    // 受保护路由组
    var protected = router.group("/api/v1", self, protectedMiddleware);

    protected.get("/auth/me", handlers.auth.me);
    protected.post("/auth/refresh", handlers.auth.refresh);

    protected.get("/strategies", handlers.strategies.list);
    protected.get("/strategies/:id", handlers.strategies.get);
    protected.post("/strategies/:id/run", handlers.strategies.run);
    protected.post("/strategies/:id/stop", handlers.strategies.stop);

    protected.post("/backtest", handlers.backtest.create);
    protected.get("/backtest/:id", handlers.backtest.get);

    protected.get("/orders", handlers.orders.list);
    protected.post("/orders", handlers.orders.create);
    protected.delete("/orders/:id", handlers.orders.cancel);

    protected.get("/positions", handlers.positions.list);

    protected.get("/account", handlers.account.get);
    protected.get("/account/balance", handlers.account.balance);

    protected.get("/metrics", handlers.metrics.get);
}
```

---

## 中间件实现

### 日志中间件

```zig
pub fn loggerMiddleware(
    ctx: *RequestContext,
    req: *httpz.Request,
    res: *httpz.Response,
) !void {
    const start = std.time.nanoTimestamp();

    // 调用下一个处理器
    defer {
        const end = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;

        // 记录请求日志
        std.log.info("[{s}] {s} {s} {d} {d:.2}ms", .{
            &ctx.request_id,
            @tagName(req.method),
            req.path,
            @intFromEnum(res.status),
            duration_ms,
        });

        // 更新指标
        ctx.server.metrics_collector.observeApiLatency(
            @tagName(req.method),
            req.path,
            duration_ms / 1000.0,
        );
        ctx.server.metrics_collector.incApiRequest(
            @tagName(req.method),
            req.path,
            @intFromEnum(res.status),
        );
    }

    return ctx.next(req, res);
}
```

### CORS 中间件

```zig
pub fn corsMiddleware(
    allowed_origins: []const []const u8,
) httpz.Middleware(RequestContext) {
    return struct {
        fn handler(
            ctx: *RequestContext,
            req: *httpz.Request,
            res: *httpz.Response,
        ) !void {
            const origin = req.headers.get("Origin");

            if (origin) |o| {
                // 检查是否允许的 origin
                for (allowed_origins) |allowed| {
                    if (std.mem.eql(u8, allowed, "*") or std.mem.eql(u8, allowed, o)) {
                        res.headers.put("Access-Control-Allow-Origin", o);
                        res.headers.put("Access-Control-Allow-Methods",
                            "GET, POST, PUT, DELETE, OPTIONS");
                        res.headers.put("Access-Control-Allow-Headers",
                            "Content-Type, Authorization");
                        res.headers.put("Access-Control-Max-Age", "86400");
                        break;
                    }
                }
            }

            // 处理预检请求
            if (req.method == .OPTIONS) {
                res.status = .no_content;
                return;
            }

            return ctx.next(req, res);
        }
    }.handler;
}
```

### 认证中间件

```zig
pub fn authMiddleware(
    ctx: *RequestContext,
    req: *httpz.Request,
    res: *httpz.Response,
) !void {
    const auth_header = req.headers.get("Authorization") orelse {
        res.status = .unauthorized;
        return res.json(.{
            .error = .{
                .code = "UNAUTHORIZED",
                .message = "Missing Authorization header",
            },
        });
    };

    if (!std.mem.startsWith(u8, auth_header, "Bearer ")) {
        res.status = .unauthorized;
        return res.json(.{
            .error = .{
                .code = "UNAUTHORIZED",
                .message = "Invalid Authorization format, expected 'Bearer <token>'",
            },
        });
    }

    const token = auth_header[7..];

    const payload = ctx.server.jwt_manager.verifyToken(token) catch |err| {
        res.status = .unauthorized;
        return res.json(.{
            .error = .{
                .code = "UNAUTHORIZED",
                .message = switch (err) {
                    error.TokenExpired => "Token expired",
                    error.InvalidSignature => "Invalid token signature",
                    else => "Invalid token",
                },
            },
        });
    };

    // 将用户 ID 添加到上下文
    ctx.user_id = payload.sub;

    return ctx.next(req, res);
}
```

---

## 性能优化

### 连接池复用

http.zig 内部实现了连接池，自动复用 HTTP 连接：

```zig
// http.zig 配置
.{
    .port = config.port,
    .address = config.host,
    .num_workers = config.workers,        // 工作线程数
    .max_connections = 1024,              // 最大连接数
    .connection_pool_size = 256,          // 连接池大小
}
```

### 零拷贝响应

使用 http.zig 的 writer 直接写入响应缓冲区：

```zig
fn sendJson(res: *httpz.Response, data: anytype) !void {
    res.headers.put("Content-Type", "application/json");

    // 直接写入响应缓冲区，避免额外分配
    const writer = res.writer();
    try std.json.stringify(data, .{}, writer);
}
```

### 路由缓存

路由使用 Trie 树结构，O(k) 查找复杂度，其中 k 是路径段数：

```
          /
         /|\
        / | \
       /  |  \
    api health metrics
     |
    v1
   /|\
  / | \
auth strategies orders
```

---

## 内存管理

### 请求级分配器

每个请求使用独立的 Arena 分配器，请求结束后统一释放：

```zig
fn handleRequest(server: *ApiServer, req: *httpz.Request, res: *httpz.Response) void {
    // 使用请求级 Arena
    var arena = std.heap.ArenaAllocator.init(server.allocator);
    defer arena.deinit();

    const ctx = RequestContext.init(server, arena.allocator());

    // 处理请求...
    // 请求结束后 arena 自动释放所有分配
}
```

### 响应缓冲区

http.zig 预分配响应缓冲区，避免频繁分配：

```zig
// 默认响应缓冲区大小
const RESPONSE_BUFFER_SIZE = 64 * 1024;  // 64KB

// 大响应自动扩展
if (response_size > RESPONSE_BUFFER_SIZE) {
    // 分配更大的缓冲区
}
```

---

## 边界情况

### 大请求体处理

```zig
const MAX_BODY_SIZE = 10 * 1024 * 1024;  // 10MB

fn readBody(req: *httpz.Request, allocator: Allocator) ![]const u8 {
    const content_length = req.headers.get("Content-Length") orelse return &.{};

    const len = std.fmt.parseInt(usize, content_length, 10) catch return error.InvalidContentLength;

    if (len > MAX_BODY_SIZE) {
        return error.BodyTooLarge;
    }

    return try req.reader().readAllAlloc(allocator, MAX_BODY_SIZE);
}
```

### 慢客户端超时

```zig
.{
    .read_timeout_ms = 30000,   // 读取超时 30s
    .write_timeout_ms = 30000, // 写入超时 30s
}
```

### 优雅关闭

```zig
pub fn stop(self: *Self) void {
    self.running.store(false, .release);

    // 等待正在处理的请求完成
    self.server.stop();

    std.log.info("API server stopped gracefully", .{});
}
```

---

## 文件结构

```
src/api/
├── mod.zig              # 模块导出
├── server.zig           # ApiServer 实现
├── router.zig           # 路由配置
├── jwt.zig              # JWT 实现
├── context.zig          # 请求上下文
├── middleware/
│   ├── mod.zig
│   ├── auth.zig         # 认证中间件
│   ├── cors.zig         # CORS 中间件
│   └── logger.zig       # 日志中间件
└── handlers/
    ├── mod.zig
    ├── health.zig
    ├── auth.zig
    ├── strategies.zig
    ├── backtest.zig
    ├── orders.zig
    ├── positions.zig
    ├── account.zig
    └── metrics.zig
```

---

*完整实现请参考: `src/api/`*
