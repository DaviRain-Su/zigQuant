# Story 047: REST API 服务

**Story ID**: STORY-047
**版本**: v1.0.0
**优先级**: P0 (关键路径)
**状态**: ✅ 已完成

---

## 概述

实现基于 Zig 标准库 (std.net + std.http) 的 REST API 服务，提供标准化 HTTP 接口供外部系统集成。这是 v1.0.0 的核心组件，其他 Story (Dashboard, Prometheus, Docker) 都依赖于此。

### 目标

1. 提供完整的 REST API (40 端点)
2. 实现 JWT Token 认证
3. 支持 CORS 跨域访问
4. **多交易所支持** - 同时连接多个交易所，支持跨交易所套利
5. **配置文件加载** - 支持 JSON 配置文件和环境变量
6. **动态数据集成** - 从真实组件获取数据 (RiskMetricsMonitor, AlertManager, etc.)
7. 请求日志和错误处理
8. API 响应时间 < 100ms (p99)

---

## 技术方案

### HTTP 服务器: std.net.Server + 自定义路由

> **重要变更**: 2025-12-28 从 httpz 迁移到 std.net
>
> **原因**: httpz 与 Zig 0.15 存在兼容性问题 - 编译器死代码消除会移除路由注册代码，导致 21/40 个 handler 返回 404。
>
> **解决方案**: 使用 Zig 标准库 `std.net.Server` 自行实现 HTTP 服务器和路由器。

```zig
// 自定义路由器实现
src/api/router.zig  // 路径匹配、参数提取
src/api/server.zig  // HTTP 解析、请求处理
```

**优势**:
- **零依赖**: 使用 Zig 标准库，无第三方兼容性问题
- **完全控制**: 自定义路由和中间件逻辑
- **稳定性**: 标准库 API 稳定，随 Zig 版本更新
- **简洁**: 移除 httpz 依赖，简化 build.zig.zon

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

### 多交易所架构

支持同时连接多个交易所，实现统一的 API 访问：

```
┌─────────────────────────────────────────────────────┐
│                   API Server                         │
├─────────────────────────────────────────────────────┤
│  ApiDependencies                                     │
│  ├── exchanges: HashMap<name, ExchangeEntry>        │
│  │   ├── "hyperliquid" → HyperliquidConnector       │
│  │   ├── "binance"     → BinanceConnector (future)  │
│  │   └── "okx"         → OkxConnector (future)      │
│  └── Methods:                                        │
│      ├── addExchange()                              │
│      ├── getExchange()                              │
│      ├── iterator()                                 │
│      └── hasExchanges()                             │
└─────────────────────────────────────────────────────┘
```

**API 查询参数**:
- `?exchange=hyperliquid` - 仅查询指定交易所
- `?exchange=all` 或无参数 - 查询所有交易所

### 配置文件支持

复用 `src/core/config.zig` 的 ConfigLoader：

```json
{
  "server": {
    "host": "127.0.0.1",
    "port": 8080
  },
  "exchanges": [
    {
      "name": "hyperliquid",
      "api_key": "0x...",
      "api_secret": "...",
      "testnet": true
    }
  ],
  "trading": {
    "max_position_size": 1000.0,
    "leverage": 1
  },
  "logging": {
    "level": "info"
  }
}
```

**启动方式**:
```bash
# 配置文件模式 (推荐)
zigquant serve -c config.json

# 环境变量模式 (向后兼容)
ZIGQUANT_HL_USER=0x... zigquant serve

# 混合模式 (命令行参数覆盖配置文件)
zigquant serve -c config.json -p 3000
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
    server.get("/version", handlers.health.version);

    // 认证端点 (无认证)
    server.post("/api/v1/auth/login", handlers.auth.login);
    server.post("/api/v1/auth/refresh", handlers.auth.refresh);
    server.get("/api/v1/auth/me", handlers.auth.me);

    // 交易所 (多交易所支持)
    server.get("/api/v1/exchanges", handlers.exchanges.list);
    server.get("/api/v1/exchanges/:name", handlers.exchanges.get);

    // 策略
    server.get("/api/v1/strategies", handlers.strategies.list);
    server.get("/api/v1/strategies/:id", handlers.strategies.get);
    server.post("/api/v1/strategies/:id/run", handlers.strategies.run);

    // 回测
    server.post("/api/v1/backtest", handlers.backtest.create);
    server.get("/api/v1/backtest/:id", handlers.backtest.get);

    // 仓位 (支持 ?exchange= 过滤)
    server.get("/api/v1/positions", handlers.positions.list);

    // 订单 (支持 ?exchange= 过滤)
    server.get("/api/v1/orders", handlers.orders.list);
    server.post("/api/v1/orders", handlers.orders.create);
    server.delete("/api/v1/orders/:id", handlers.orders.cancel);

    // 账户 (支持 ?exchange= 过滤)
    server.get("/api/v1/account", handlers.account.get);
    server.get("/api/v1/account/balance", handlers.account.balance);

    // 指标
    server.get("/metrics", handlers.metrics.prometheus);
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

- [x] 健康检查端点 (/health, /ready, /version)
- [x] JWT 认证 (登录, 刷新, 验证)
- [x] **多交易所支持** (exchanges 端点, ?exchange= 过滤)
- [x] **配置文件加载** (-c/--config 参数)
- [x] 策略管理 API (列表, 详情, 运行)
- [x] 回测 API (创建, 查询)
- [x] 订单 API (列表, 创建, 取消) - 支持多交易所
- [x] 仓位 API (列表) - 支持多交易所
- [x] 账户 API (信息, 余额) - 支持多交易所
- [x] 指标 API (Prometheus 格式)
- [x] CORS 中间件
- [x] 请求日志中间件

### 已实现端点 (30个)

| 端点 | 方法 | 描述 |
|------|------|------|
| /health | GET | 健康检查 |
| /ready | GET | 就绪检查 |
| /version | GET | 版本信息 |
| /api/v1/auth/login | POST | 用户登录 |
| /api/v1/auth/refresh | POST | 刷新 Token |
| /api/v1/auth/me | GET | 当前用户信息 |
| /api/v1/exchanges | GET | 交易所列表 |
| /api/v1/exchanges/:name | GET | 交易所详情 |
| /api/v1/strategies | GET | 策略列表 |
| /api/v1/strategies/:id | GET | 策略详情 |
| /api/v1/strategies/:id/run | POST | 运行策略 |
| /api/v1/backtest | POST | 创建回测 |
| /api/v1/backtest/:id | GET | 回测结果 |
| /api/v1/positions | GET | 仓位列表 (支持 ?exchange=) |
| /api/v1/orders | GET | 订单列表 (支持 ?exchange=) |
| /api/v1/orders | POST | 创建订单 |
| /api/v1/orders/:id | DELETE | 取消订单 |
| /api/v1/account | GET | 账户信息 |
| /api/v1/account/balance | GET | 账户余额 (支持 ?exchange=) |
| /metrics | GET | Prometheus 指标 |
| **/api/v2/live** | **GET** | **实盘交易会话列表** |
| **/api/v2/live** | **POST** | **启动实盘交易会话** |
| **/api/v2/live/:id** | **GET** | **实盘会话详情** |
| **/api/v2/live/:id** | **DELETE** | **停止实盘会话** |
| **/api/v2/live/:id/pause** | **POST** | **暂停实盘会话** |
| **/api/v2/live/:id/resume** | **POST** | **恢复实盘会话** |
| **/api/v2/live/:id/subscribe** | **POST** | **订阅交易对** |
| **/api/v2/ai/config** | **GET** | **获取 AI 配置状态** |
| **/api/v2/ai/config** | **POST** | **更新 AI 配置** |
| **/api/v2/ai/enable** | **POST** | **启用 AI 客户端** |
| **/api/v2/ai/disable** | **POST** | **禁用 AI 客户端** |

#### Live Trading API (v0.9.1 新增)

实盘交易 API 使用 `/api/v2/live` 前缀，支持完整的会话生命周期管理：

```bash
# 列出所有实盘会话
curl http://localhost:8080/api/v2/live

# 启动新的实盘会话
curl -X POST http://localhost:8080/api/v2/live \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "btc_dual_ma",
    "strategy_type": "dual_ma",
    "exchange": "hyperliquid",
    "symbol": "BTC",
    "mode": "paper",
    "initial_capital": 10000.0,
    "params": {
      "fast_period": 10,
      "slow_period": 30
    }
  }'

# 查看会话详情
curl http://localhost:8080/api/v2/live/btc_dual_ma

# 暂停会话
curl -X POST http://localhost:8080/api/v2/live/btc_dual_ma/pause

# 恢复会话
curl -X POST http://localhost:8080/api/v2/live/btc_dual_ma/resume

# 停止会话
curl -X DELETE http://localhost:8080/api/v2/live/btc_dual_ma
```

**LiveRequest 参数说明**:

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| session_id | string | 是 | 唯一会话标识符 |
| strategy_type | string | 是 | 策略类型 (dual_ma, rsi_mean_reversion, bollinger_breakout, etc.) |
| exchange | string | 是 | 交易所名称 (hyperliquid) |
| symbol | string | 是 | 交易对 (BTC, ETH) |
| mode | string | 否 | 交易模式: "paper" (默认) 或 "live" |
| initial_capital | float | 否 | 初始资金 (默认 10000.0) |
| params | object | 否 | 策略参数 |

**LiveStatus 返回值**:

```json
{
  "session_id": "btc_dual_ma",
  "status": "running",
  "strategy_type": "dual_ma",
  "exchange": "hyperliquid",
  "symbol": "BTC",
  "mode": "paper",
  "stats": {
    "ticks_processed": 1234,
    "orders_placed": 5,
    "orders_filled": 3,
    "current_pnl": 150.50,
    "start_time": 1735344000000,
    "uptime_seconds": 3600
  }
}

#### AI Configuration API (v0.9.1 新增)

AI 配置 API 使用 `/api/v2/ai` 前缀，支持运行时动态配置 AI 提供商和模型：

```bash
# 获取 AI 配置状态
curl http://localhost:8080/api/v2/ai/config

# Response:
{
  "success": true,
  "data": {
    "enabled": false,
    "provider": "openai",
    "model_id": "gpt-4o",
    "api_endpoint": null,
    "has_api_key": false,
    "connected": false
  }
}

# 更新 AI 配置
curl -X POST http://localhost:8080/api/v2/ai/config \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "anthropic",
    "model_id": "claude-sonnet-4-5",
    "api_endpoint": "https://api.anthropic.com",
    "api_key": "sk-ant-xxx..."
  }'

# 启用 AI (初始化 LLM 客户端)
curl -X POST http://localhost:8080/api/v2/ai/enable

# Response:
{
  "success": true,
  "data": {
    "enabled": true,
    "provider": "anthropic",
    "model_id": "claude-sonnet-4-5",
    "message": "AI enabled successfully"
  }
}

# 禁用 AI
curl -X POST http://localhost:8080/api/v2/ai/disable
```

**支持的 AI Provider**:

| Provider | model_id 示例 | api_endpoint |
|----------|--------------|--------------|
| openai | gpt-4o, gpt-4o-mini | https://api.openai.com/v1 |
| anthropic | claude-sonnet-4-5, claude-haiku | https://api.anthropic.com |
| lmstudio | local-model | http://127.0.0.1:1234/v1 |
| ollama | llama3, mistral | http://localhost:11434/v1 |
| deepseek | deepseek-chat | https://api.deepseek.com/v1 |
| custom | 自定义 | 自定义 URL |

**使用 hybrid_ai 策略**:

配置好 AI 后，可以启动使用 AI 的混合策略：

```bash
curl -X POST http://localhost:8080/api/v2/strategy \
  -H "Content-Type: application/json" \
  -d '{
    "strategy": "hybrid_ai",
    "symbol": "BTC-USDT",
    "timeframe": "1h",
    "mode": "paper",
    "params": {
      "rsi_period": 14,
      "sma_period": 20,
      "ai_weight": 0.4,
      "technical_weight": 0.6,
      "min_ai_confidence": 0.6
    }
  }'
```

### 性能要求

- [x] 响应时间 < 100ms (p99) - 真实交易所 API 调用
- [ ] 支持 1000+ 并发连接
- [x] 内存占用合理

### 质量要求

- [ ] 单元测试覆盖率 > 80%
- [x] 零编译警告
- [x] 零内存泄漏 (使用 GeneralPurposeAllocator)

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

## 更新日志

### 2025-12-29 (第六次更新) - AI Configuration API

- **新增 AI Configuration API** (3 个端点):
  - `GET /api/v2/ai/config` - 获取 AI 配置状态
  - `POST /api/v2/ai/config` - 更新 AI 配置
  - `POST /api/v2/ai/enable` - 启用 AI 客户端
  - `POST /api/v2/ai/disable` - 禁用 AI 客户端

- **StrategyFactory 扩展**:
  - 添加 `hybrid_ai` 策略支持
  - LLM 客户端注入机制

- **EngineManager AI 管理**:
  - `AIRuntimeConfig` 运行时配置
  - `configureAI()` / `updateAIConfig()` 配置方法
  - `initAIClient()` / `disableAI()` 生命周期管理

- **端点总数**: 27 → 30

### 2025-12-29 (第五次更新) - Live Trading API

- **新增 Live Trading API** (7 个端点):
  - `GET /api/v2/live` - 列出所有实盘会话
  - `POST /api/v2/live` - 启动新会话
  - `GET /api/v2/live/:id` - 会话详情
  - `DELETE /api/v2/live/:id` - 停止会话
  - `POST /api/v2/live/:id/pause` - 暂停会话
  - `POST /api/v2/live/:id/resume` - 恢复会话
  - `POST /api/v2/live/:id/subscribe` - 订阅交易对

- **EngineManager 集成**:
  - `live_runners: HashMap` 管理实盘会话
  - 支持 Paper/Live 两种交易模式
  - Kill Switch 联动停止所有实盘会话

- **端点总数**: 20 → 27

### 2025-12-28 (第四次更新) - 动态数据集成

- **Risk Handlers 动态数据**:
  - `handleRiskMetrics` - 使用真实 RiskMetricsMonitor 计算 VaR、Drawdown、Sharpe
  - `handleRiskVaR` - 返回真实 VaR 95%/99% 数据
  - `handleRiskDrawdown` - 返回真实当前/最大回撤
  - `handleRiskSharpe` - 返回真实 Sharpe/Sortino/Calmar 比率
  - `handleRiskReport` - 返回完整风险报告

- **Alert Handlers 动态数据**:
  - `handleAlertsList` - 返回真实告警历史 (最近 100 条)
  - `handleAlertsStats` - 返回真实告警统计 (按级别分类)

- **Strategy Handlers 动态数据**:
  - `handleStrategiesList` - 返回 6 个真实策略 (dual_ma, rsi_mean_reversion, bollinger_breakout, triple_ma, macd_divergence, hybrid_ai)
  - `handleStrategyGet` - 使用 advanced.zig 获取策略详情
  - `handleStrategyParams` - 返回完整参数定义 (类型、默认值、范围)

- **Indicator Handlers 动态数据**:
  - `handleIndicatorsList` - 返回 12 个真实指标 (SMA, EMA, RSI, MACD, Bollinger, ATR, ADX, CCI, Williams%R, OBV, VWAP, Parabolic SAR)
  - `handleIndicatorGet` - 返回指标详情 (分类、参数、输出类型)

- **Exchange/Trading Handlers 动态数据**:
  - `handleExchangesList` - 从 ApiDependencies 获取真实交易所列表
  - `handlePaperTradingStatus` - 返回真实 paper_sessions 数量

- **智能降级**: 当组件未配置时返回 `note` 字段说明，而非假数据

### 2025-12-28 (第三次更新) - 从 httpz 迁移到 std.net

- **移除 httpz 依赖**: 解决 Zig 0.15 死代码消除导致路由注册被移除的问题
- **新增自定义路由器** (`src/api/router.zig`):
  - 支持路径参数 (`:id`)
  - 支持查询字符串解析
  - 支持所有 HTTP 方法
- **重写 server.zig** 使用 `std.net.Server`:
  - 手动 HTTP 请求解析
  - 手动 HTTP 响应构建
  - JSON 序列化使用 `std.json.Stringify`
- **修复中间件**: 移除 cors.zig 和 auth.zig 中的 httpz 引用
- **所有 40 个路由正常工作**

### 2025-12-28 (第二次更新)

- 订单创建端点 (POST /api/v1/orders) 集成真实交易所 createOrder()
- 订单取消端点 (DELETE /api/v1/orders/:id) 集成真实交易所 cancelOrder()
- 增强 /metrics 端点，添加交易所实时指标:
  - zigquant_exchange_connected - 交易所连接状态
  - zigquant_positions_count/pnl_total/margin_total - 仓位指标
  - zigquant_orders_open_count - 订单指标
  - zigquant_balance_total/available - 余额指标
- 添加 Side, OrderType, TradingPair, Decimal, OrderRequest 类型导出

### 2025-12-28 (第一次更新)

- 添加多交易所支持 (ApiDependencies HashMap)
- 新增 /api/v1/exchanges 端点
- 所有交易相关端点支持 ?exchange= 过滤
- 添加 -c/--config 配置文件加载
- 复用 src/core/config.zig 的 ConfigLoader
- 修复 Zig 0.15 ArrayList 兼容性问题

---

## 已知限制 / 未来改进

### 当前限制

1. **单线程处理**: 当前使用阻塞式请求处理，不支持并发连接
2. **无 WebSocket**: 仅支持 HTTP，实时推送需要轮询
3. **基础错误处理**: 错误响应格式简单，无 request_id 追踪

### 未来改进 (v1.1.0+)

- [ ] 多线程连接处理 (线程池)
- [ ] WebSocket 实时推送 (仓位变化、订单状态)
- [ ] 请求 ID 追踪 (X-Request-Id)
- [ ] 速率限制 (Rate Limiting)
- [ ] API 版本协商 (Accept-Version header)
- [ ] OpenAPI/Swagger 文档自动生成

---

*最后更新: 2025-12-28*
