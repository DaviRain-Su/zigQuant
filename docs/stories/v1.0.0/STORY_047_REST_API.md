# Story 047: REST API 服务

**Story ID**: STORY-047
**版本**: v1.0.0
**优先级**: P0 (关键路径)
**状态**: 📋 待开始

---

## 概述

实现基于 http.zig 的 REST API 服务，提供标准化 HTTP 接口供外部系统集成。这是 v1.0.0 的核心组件，其他 Story (Dashboard, Prometheus, Docker) 都依赖于此。

### 目标

1. 提供完整的 REST API (15+ 端点)
2. 实现 JWT Token 认证
3. 支持 CORS 跨域访问
4. 请求日志和错误处理
5. API 响应时间 < 100ms (p99)

---

## 技术方案

### HTTP 服务器: http.zig

```zig
// build.zig.zon
.httpz = .{
    .url = "https://github.com/karlseguin/http.zig/archive/refs/heads/master.tar.gz",
},
```

**选择理由**:
- 性能: 140K+ req/sec
- 纯 Zig 实现，无 C 依赖
- 内置 JSON 支持
- 中间件架构

### 认证: JWT Token (HS256)

```
Authorization: Bearer <token>
```

**Token 结构**:
```json
{
  "header": {"alg": "HS256", "typ": "JWT"},
  "payload": {"sub": "user_id", "iat": 1735344000, "exp": 1735430400},
  "signature": "..."
}
```

---

## 文件结构

```
src/api/
├── mod.zig              # 模块导出
├── server.zig           # ApiServer 实现
├── router.zig           # 路由配置
├── jwt.zig              # JWT 生成/验证
├── middleware/
│   ├── mod.zig
│   ├── auth.zig         # JWT 认证中间件
│   ├── cors.zig         # CORS 中间件
│   └── logger.zig       # 请求日志中间件
└── handlers/
    ├── mod.zig
    ├── health.zig       # 健康检查
    ├── auth.zig         # 登录/Token 刷新
    ├── strategies.zig   # 策略管理
    ├── backtest.zig     # 回测
    ├── positions.zig    # 仓位
    ├── orders.zig       # 订单
    ├── account.zig      # 账户
    └── metrics.zig      # 指标
```

---

## 核心实现

### ApiServer

```zig
// src/api/server.zig
const std = @import("std");
const httpz = @import("httpz");

pub const ApiServer = struct {
    allocator: Allocator,
    server: httpz.Server(.{}),
    config: ApiConfig,
    jwt_manager: JwtManager,

    // 依赖注入
    strategy_registry: *StrategyRegistry,
    backtest_engine: *BacktestEngine,
    trading_engine: ?*LiveTradingEngine,

    const Self = @This();

    pub fn init(allocator: Allocator, config: ApiConfig, deps: Dependencies) !*Self {
        const self = try allocator.create(Self);

        self.* = .{
            .allocator = allocator,
            .server = try httpz.Server(.{}).init(allocator, .{
                .port = config.port,
                .address = config.host,
            }),
            .config = config,
            .jwt_manager = JwtManager.init(allocator, config.jwt_secret, config.jwt_expiry_hours),
            .strategy_registry = deps.strategy_registry,
            .backtest_engine = deps.backtest_engine,
            .trading_engine = deps.trading_engine,
        };

        // 配置中间件
        self.server.middleware(middleware.logger);
        self.server.middleware(middleware.cors(config.cors_origins));

        // 配置路由
        router.setup(&self.server, self);

        return self;
    }

    pub fn start(self: *Self) !void {
        std.log.info("API Server starting on {s}:{d}", .{self.config.host, self.config.port});
        try self.server.listen();
    }

    pub fn stop(self: *Self) void {
        self.server.stop();
    }

    pub fn deinit(self: *Self) void {
        self.server.deinit();
        self.allocator.destroy(self);
    }
};

pub const ApiConfig = struct {
    host: []const u8 = "0.0.0.0",
    port: u16 = 8080,
    workers: u16 = 4,
    jwt_secret: []const u8,
    jwt_expiry_hours: u32 = 24,
    cors_origins: []const []const u8 = &.{"*"},
};

pub const Dependencies = struct {
    strategy_registry: *StrategyRegistry,
    backtest_engine: *BacktestEngine,
    trading_engine: ?*LiveTradingEngine = null,
};
```

### JWT Manager

```zig
// src/api/jwt.zig
const std = @import("std");
const crypto = std.crypto;

pub const JwtManager = struct {
    allocator: Allocator,
    secret: []const u8,
    expiry_hours: u32,

    const Self = @This();

    pub fn init(allocator: Allocator, secret: []const u8, expiry_hours: u32) Self {
        return .{
            .allocator = allocator,
            .secret = secret,
            .expiry_hours = expiry_hours,
        };
    }

    /// 生成 JWT Token
    pub fn generateToken(self: *Self, user_id: []const u8) ![]const u8 {
        const now = std.time.timestamp();
        const exp = now + @as(i64, self.expiry_hours) * 3600;

        // Header
        const header_json = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";
        const header_b64 = try base64UrlEncode(self.allocator, header_json);
        defer self.allocator.free(header_b64);

        // Payload
        const payload_json = try std.fmt.allocPrint(self.allocator,
            "{{\"sub\":\"{s}\",\"iat\":{d},\"exp\":{d}}}",
            .{user_id, now, exp}
        );
        defer self.allocator.free(payload_json);
        const payload_b64 = try base64UrlEncode(self.allocator, payload_json);
        defer self.allocator.free(payload_b64);

        // Signature
        const message = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{header_b64, payload_b64});
        defer self.allocator.free(message);

        var hmac = crypto.auth.hmac.sha2.HmacSha256.init(self.secret);
        hmac.update(message);
        var signature: [32]u8 = undefined;
        hmac.final(&signature);

        const sig_b64 = try base64UrlEncode(self.allocator, &signature);
        defer self.allocator.free(sig_b64);

        return try std.fmt.allocPrint(self.allocator, "{s}.{s}.{s}",
            .{header_b64, payload_b64, sig_b64});
    }

    /// 验证 JWT Token
    pub fn verifyToken(self: *Self, token: []const u8) !JwtPayload {
        var iter = std.mem.splitScalar(u8, token, '.');

        const header_b64 = iter.next() orelse return error.InvalidToken;
        const payload_b64 = iter.next() orelse return error.InvalidToken;
        const sig_b64 = iter.next() orelse return error.InvalidToken;

        // 验证签名
        const message = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{header_b64, payload_b64});
        defer self.allocator.free(message);

        var hmac = crypto.auth.hmac.sha2.HmacSha256.init(self.secret);
        hmac.update(message);
        var expected_sig: [32]u8 = undefined;
        hmac.final(&expected_sig);

        const actual_sig = try base64UrlDecode(self.allocator, sig_b64);
        defer self.allocator.free(actual_sig);

        if (!std.mem.eql(u8, &expected_sig, actual_sig)) {
            return error.InvalidSignature;
        }

        // 解析 Payload
        const payload_json = try base64UrlDecode(self.allocator, payload_b64);
        defer self.allocator.free(payload_json);

        const parsed = try std.json.parseFromSlice(JwtPayload, self.allocator, payload_json, .{});
        defer parsed.deinit();

        // 验证过期时间
        if (parsed.value.exp < std.time.timestamp()) {
            return error.TokenExpired;
        }

        return parsed.value;
    }
};

pub const JwtPayload = struct {
    sub: []const u8,  // user_id
    iat: i64,         // issued at
    exp: i64,         // expires at
};
```

### Router

```zig
// src/api/router.zig
const httpz = @import("httpz");
const handlers = @import("handlers/mod.zig");

pub fn setup(server: anytype, ctx: *ApiServer) void {
    // 健康检查 (无认证)
    server.get("/health", handlers.health.get);
    server.get("/ready", handlers.health.ready);

    // 认证端点 (无认证)
    server.post("/api/v1/auth/login", handlers.auth.login);
    server.post("/api/v1/auth/refresh", handlers.auth.refresh);

    // 受保护的路由 (需要认证)
    const protected = server.router().group("/api/v1");
    protected.middleware(middleware.auth(ctx.jwt_manager));

    // 用户
    protected.get("/auth/me", handlers.auth.me);

    // 策略
    protected.get("/strategies", handlers.strategies.list);
    protected.get("/strategies/:id", handlers.strategies.get);
    protected.post("/strategies/:id/run", handlers.strategies.run);

    // 回测
    protected.post("/backtest", handlers.backtest.create);
    protected.get("/backtest/:id", handlers.backtest.get);

    // 仓位
    protected.get("/positions", handlers.positions.list);

    // 订单
    protected.get("/orders", handlers.orders.list);
    protected.post("/orders", handlers.orders.create);
    protected.delete("/orders/:id", handlers.orders.cancel);

    // 账户
    protected.get("/account", handlers.account.get);
    protected.get("/account/balance", handlers.account.balance);

    // 指标
    protected.get("/metrics", handlers.metrics.get);
    server.get("/metrics", handlers.metrics.prometheus);  // Prometheus 无认证
}
```

### 中间件

#### 认证中间件

```zig
// src/api/middleware/auth.zig
pub fn auth(jwt_manager: *JwtManager) httpz.Middleware {
    return struct {
        fn handle(ctx: *httpz.Request.Context, req: *httpz.Request, res: *httpz.Response) !void {
            const auth_header = req.headers.get("Authorization") orelse {
                res.status = .unauthorized;
                try res.json(.{ .error = "Missing Authorization header" });
                return;
            };

            if (!std.mem.startsWith(u8, auth_header, "Bearer ")) {
                res.status = .unauthorized;
                try res.json(.{ .error = "Invalid Authorization format" });
                return;
            }

            const token = auth_header[7..];
            const payload = jwt_manager.verifyToken(token) catch |err| {
                res.status = .unauthorized;
                try res.json(.{ .error = @errorName(err) });
                return;
            };

            // 将用户信息附加到上下文
            ctx.user_id = payload.sub;
            return ctx.next(req, res);
        }
    }.handle;
}
```

#### CORS 中间件

```zig
// src/api/middleware/cors.zig
pub fn cors(allowed_origins: []const []const u8) httpz.Middleware {
    return struct {
        fn handle(ctx: *httpz.Request.Context, req: *httpz.Request, res: *httpz.Response) !void {
            const origin = req.headers.get("Origin") orelse {
                return ctx.next(req, res);
            };

            // 检查是否允许的 origin
            for (allowed_origins) |allowed| {
                if (std.mem.eql(u8, allowed, "*") or std.mem.eql(u8, allowed, origin)) {
                    res.headers.put("Access-Control-Allow-Origin", origin);
                    res.headers.put("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
                    res.headers.put("Access-Control-Allow-Headers", "Content-Type, Authorization");
                    break;
                }
            }

            // 处理 OPTIONS 预检请求
            if (req.method == .OPTIONS) {
                res.status = .no_content;
                return;
            }

            return ctx.next(req, res);
        }
    }.handle;
}
```

#### 日志中间件

```zig
// src/api/middleware/logger.zig
pub fn logger(ctx: *httpz.Request.Context, req: *httpz.Request, res: *httpz.Response) !void {
    const start = std.time.nanoTimestamp();

    defer {
        const end = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;

        std.log.info("{s} {s} {d} {d:.2}ms", .{
            @tagName(req.method),
            req.path,
            @intFromEnum(res.status),
            duration_ms,
        });
    }

    return ctx.next(req, res);
}
```

---

## Handler 示例

### 健康检查

```zig
// src/api/handlers/health.zig
pub fn get(req: *Request, res: *Response) !void {
    _ = req;
    try res.json(.{
        .status = "healthy",
        .version = "1.0.0",
        .timestamp = std.time.timestamp(),
    });
}

pub fn ready(req: *Request, res: *Response) !void {
    _ = req;
    // 检查依赖服务
    const ready_status = checkDependencies();

    if (ready_status) {
        try res.json(.{ .ready = true });
    } else {
        res.status = .service_unavailable;
        try res.json(.{ .ready = false, .reason = "Dependencies not ready" });
    }
}
```

### 策略管理

```zig
// src/api/handlers/strategies.zig
pub fn list(ctx: *Context, req: *Request, res: *Response) !void {
    _ = req;
    const strategies = ctx.server.strategy_registry.list();

    var result = std.ArrayList(StrategyInfo).init(ctx.allocator);
    defer result.deinit();

    for (strategies) |strategy| {
        try result.append(.{
            .id = strategy.id,
            .name = strategy.name,
            .status = @tagName(strategy.status),
            .pair = strategy.pair,
            .timeframe = @tagName(strategy.timeframe),
        });
    }

    try res.json(.{
        .strategies = result.items,
        .total = strategies.len,
    });
}

pub fn run(ctx: *Context, req: *Request, res: *Response) !void {
    const id = req.params.get("id") orelse {
        res.status = .bad_request;
        return res.json(.{ .error = "Missing strategy ID" });
    };

    const strategy = ctx.server.strategy_registry.get(id) orelse {
        res.status = .not_found;
        return res.json(.{ .error = "Strategy not found" });
    };

    try strategy.start();

    try res.json(.{
        .id = id,
        .status = "running",
        .message = "Strategy started successfully",
    });
}
```

### 回测

```zig
// src/api/handlers/backtest.zig
const BacktestRequest = struct {
    strategy_id: []const u8,
    start_date: []const u8,
    end_date: []const u8,
    initial_capital: f64 = 10000.0,
};

pub fn create(ctx: *Context, req: *Request, res: *Response) !void {
    const body = try req.json(BacktestRequest);

    const strategy = ctx.server.strategy_registry.get(body.strategy_id) orelse {
        res.status = .not_found;
        return res.json(.{ .error = "Strategy not found" });
    };

    // 异步执行回测
    const backtest_id = try ctx.server.backtest_engine.submit(.{
        .strategy = strategy,
        .start_date = body.start_date,
        .end_date = body.end_date,
        .initial_capital = body.initial_capital,
    });

    res.status = .accepted;
    try res.json(.{
        .id = backtest_id,
        .status = "pending",
        .message = "Backtest submitted",
    });
}

pub fn get(ctx: *Context, req: *Request, res: *Response) !void {
    const id = req.params.get("id") orelse {
        res.status = .bad_request;
        return res.json(.{ .error = "Missing backtest ID" });
    };

    const result = ctx.server.backtest_engine.getResult(id) orelse {
        res.status = .not_found;
        return res.json(.{ .error = "Backtest not found" });
    };

    try res.json(.{
        .id = id,
        .status = @tagName(result.status),
        .metrics = if (result.metrics) |m| .{
            .total_return = m.total_return,
            .sharpe_ratio = m.sharpe_ratio,
            .max_drawdown = m.max_drawdown,
            .win_rate = m.win_rate,
            .total_trades = m.total_trades,
        } else null,
        .error = result.error_message,
    });
}
```

---

## API 响应格式

### 成功响应

```json
{
  "data": { ... },
  "meta": {
    "timestamp": 1735344000,
    "request_id": "abc123"
  }
}
```

### 错误响应

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid request body",
    "details": { ... }
  },
  "meta": {
    "timestamp": 1735344000,
    "request_id": "abc123"
  }
}
```

### HTTP 状态码

| 状态码 | 含义 |
|--------|------|
| 200 | 成功 |
| 201 | 创建成功 |
| 202 | 已接受 (异步处理) |
| 400 | 请求错误 |
| 401 | 未认证 |
| 403 | 权限不足 |
| 404 | 资源不存在 |
| 500 | 服务器错误 |

---

## 配置

### 环境变量

```bash
# 服务配置
ZIGQUANT_API_HOST=0.0.0.0
ZIGQUANT_API_PORT=8080
ZIGQUANT_API_WORKERS=4

# JWT 配置
ZIGQUANT_JWT_SECRET=your-secret-key-here
ZIGQUANT_JWT_EXPIRY_HOURS=24

# CORS 配置
ZIGQUANT_CORS_ORIGINS=http://localhost:3000,https://dashboard.example.com
```

### JSON 配置

```json
{
  "api": {
    "host": "0.0.0.0",
    "port": 8080,
    "workers": 4,
    "jwt_secret": "your-secret-key-here",
    "jwt_expiry_hours": 24,
    "cors_origins": ["*"]
  }
}
```

---

## 测试

### 单元测试

```zig
// src/api/jwt.zig
test "JwtManager generates valid token" {
    const allocator = std.testing.allocator;
    var jwt = JwtManager.init(allocator, "test-secret", 24);

    const token = try jwt.generateToken("user123");
    defer allocator.free(token);

    const payload = try jwt.verifyToken(token);
    try std.testing.expectEqualStrings("user123", payload.sub);
}

test "JwtManager rejects expired token" {
    // ...
}

test "JwtManager rejects invalid signature" {
    // ...
}
```

### 集成测试

```bash
# 健康检查
curl http://localhost:8080/health

# 登录获取 Token
TOKEN=$(curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}' \
  | jq -r '.token')

# 获取策略列表
curl http://localhost:8080/api/v1/strategies \
  -H "Authorization: Bearer $TOKEN"

# 执行回测
curl -X POST http://localhost:8080/api/v1/backtest \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "strategy_id": "sma_cross",
    "start_date": "2024-01-01",
    "end_date": "2024-12-31",
    "initial_capital": 10000
  }'
```

---

## 验收标准

### 功能要求

- [x] 健康检查端点 (/health, /ready)
- [ ] JWT 认证 (登录, 刷新, 验证)
- [ ] 策略管理 API (列表, 详情, 运行)
- [ ] 回测 API (创建, 查询)
- [ ] 订单 API (列表, 创建, 取消)
- [ ] 仓位 API (列表)
- [ ] 账户 API (信息, 余额)
- [ ] 指标 API (JSON, Prometheus)
- [ ] CORS 中间件
- [ ] 请求日志

### 性能要求

- [ ] 响应时间 < 100ms (p99)
- [ ] 支持 1000+ 并发连接
- [ ] 内存占用 < 50MB

### 质量要求

- [ ] 单元测试覆盖率 > 80%
- [ ] 零编译警告
- [ ] 零内存泄漏

---

## 依赖

- **http.zig** - HTTP 服务器
- **std.crypto** - JWT 签名
- **std.json** - JSON 处理

---

## 相关文档

- [v1.0.0 Overview](./OVERVIEW.md)
- [API 端点文档](../../features/api/endpoints.md)
- [认证文档](../../features/api/authentication.md)

---

*最后更新: 2025-12-28*
