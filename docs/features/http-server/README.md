# HTTP Server - REST API 服务

> 基于 http.zig 的高性能 REST API 服务

**状态**: 📋 待开始
**版本**: v1.0.0
**Story**: [Story 047: REST API](../../stories/v1.0.0/STORY_047_REST_API.md)
**最后更新**: 2025-12-28

---

## 概述

zigQuant HTTP Server 模块提供完整的 REST API 服务，基于 [http.zig](https://github.com/karlseguin/http.zig) 实现，支持 JWT 认证、CORS、请求日志等功能。

### 为什么需要 HTTP Server？

- **外部集成**: 允许外部系统通过标准 HTTP API 与 zigQuant 交互
- **监控集成**: 提供 Prometheus 格式指标导出
- **自动化**: 支持程序化策略管理和回测

### 核心特性

- **高性能**: 140K+ req/sec (http.zig 基准)
- **JWT 认证**: HS256 签名，可配置过期时间
- **CORS 支持**: 可配置跨域访问策略
- **中间件架构**: 可扩展的请求处理链
- **结构化响应**: 统一的 JSON 响应格式

---

## 快速开始

### 基本使用

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 创建依赖
    var registry = try zigQuant.StrategyRegistry.init(allocator);
    defer registry.deinit();

    var backtest_engine = try zigQuant.BacktestEngine.init(allocator, .{});
    defer backtest_engine.deinit();

    // 2. 配置 API 服务
    const config = zigQuant.ApiConfig{
        .host = "0.0.0.0",
        .port = 8080,
        .jwt_secret = "your-secret-key-at-least-32-bytes",
        .jwt_expiry_hours = 24,
        .cors_origins = &.{"http://localhost:3000"},
    };

    // 3. 创建服务器
    var server = try zigQuant.ApiServer.init(allocator, config, .{
        .strategy_registry = &registry,
        .backtest_engine = &backtest_engine,
        .trading_engine = null,
    });
    defer server.deinit();

    // 4. 启动服务
    std.log.info("Starting API server on {s}:{d}", .{config.host, config.port});
    try server.start();
}
```

### CLI 启动

```bash
# 使用默认配置启动
zigquant serve

# 指定配置文件
zigquant serve --config /etc/zigquant/config.json

# 指定端口
zigquant serve --port 9000
```

---

## 相关文档

- [REST API 端点](./endpoints.md) - 完整的端点详情和请求/响应示例
- [JWT 认证](./authentication.md) - 认证流程和安全最佳实践
- [API 参考](./api.md) - Zig API 文档 (ApiServer, JwtManager)
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 核心 API

### ApiServer

```zig
pub const ApiServer = struct {
    allocator: Allocator,
    server: httpz.Server(.{}),
    config: ApiConfig,
    jwt_manager: JwtManager,
    metrics_collector: MetricsCollector,

    // 依赖注入
    strategy_registry: *StrategyRegistry,
    backtest_engine: *BacktestEngine,
    trading_engine: ?*LiveTradingEngine,

    pub fn init(allocator: Allocator, config: ApiConfig, deps: Dependencies) !*ApiServer;
    pub fn start(self: *ApiServer) !void;
    pub fn stop(self: *ApiServer) void;
    pub fn deinit(self: *ApiServer) void;
};
```

### ApiConfig

```zig
pub const ApiConfig = struct {
    host: []const u8 = "0.0.0.0",
    port: u16 = 8080,
    workers: u16 = 4,
    jwt_secret: []const u8,
    jwt_expiry_hours: u32 = 24,
    cors_origins: []const []const u8 = &.{"*"},
    read_timeout_ms: u32 = 30000,
    write_timeout_ms: u32 = 30000,
};
```

### JwtManager

```zig
pub const JwtManager = struct {
    allocator: Allocator,
    secret: []const u8,
    expiry_hours: u32,

    pub fn init(allocator: Allocator, secret: []const u8, expiry_hours: u32) JwtManager;
    pub fn generateToken(self: *JwtManager, user_id: []const u8) ![]const u8;
    pub fn verifyToken(self: *JwtManager, token: []const u8) !JwtPayload;
};

pub const JwtPayload = struct {
    sub: []const u8,  // user_id
    iat: i64,         // issued at
    exp: i64,         // expires at
};
```

---

## API 端点

### 健康检查

| 方法 | 路径 | 认证 | 描述 |
|------|------|------|------|
| GET | `/health` | 否 | 服务健康状态 |
| GET | `/ready` | 否 | 就绪检查 |

### 认证

| 方法 | 路径 | 认证 | 描述 |
|------|------|------|------|
| POST | `/api/v1/auth/login` | 否 | 用户登录 |
| POST | `/api/v1/auth/refresh` | 是 | 刷新 Token |
| GET | `/api/v1/auth/me` | 是 | 当前用户信息 |

### 策略

| 方法 | 路径 | 认证 | 描述 |
|------|------|------|------|
| GET | `/api/v1/strategies` | 是 | 策略列表 |
| GET | `/api/v1/strategies/:id` | 是 | 策略详情 |
| POST | `/api/v1/strategies/:id/run` | 是 | 启动策略 |
| POST | `/api/v1/strategies/:id/stop` | 是 | 停止策略 |

### 回测

| 方法 | 路径 | 认证 | 描述 |
|------|------|------|------|
| POST | `/api/v1/backtest` | 是 | 执行回测 |
| GET | `/api/v1/backtest/:id` | 是 | 获取结果 |

### 交易

| 方法 | 路径 | 认证 | 描述 |
|------|------|------|------|
| GET | `/api/v1/orders` | 是 | 订单列表 |
| POST | `/api/v1/orders` | 是 | 创建订单 |
| DELETE | `/api/v1/orders/:id` | 是 | 取消订单 |
| GET | `/api/v1/positions` | 是 | 仓位列表 |

### 监控

| 方法 | 路径 | 认证 | 描述 |
|------|------|------|------|
| GET | `/api/v1/metrics` | 是 | JSON 格式指标 |
| GET | `/metrics` | 否 | Prometheus 格式 |

---

## 最佳实践

### DO

```zig
// 使用环境变量配置敏感信息
const secret = std.posix.getenv("ZIGQUANT_JWT_SECRET") orelse {
    std.log.err("JWT_SECRET not set", .{});
    return error.MissingConfig;
};

// 配置合理的超时
const config = ApiConfig{
    .read_timeout_ms = 30000,
    .write_timeout_ms = 30000,
};

// 使用依赖注入
var server = try ApiServer.init(allocator, config, .{
    .strategy_registry = &registry,
    .backtest_engine = &engine,
});
```

### DON'T

```zig
// 不要硬编码密钥
const config = ApiConfig{
    .jwt_secret = "hardcoded-secret",  // 错误!
};

// 不要禁用认证
// 所有业务 API 都应该需要认证
```

---

## 使用场景

### 适用

- REST API 服务
- 自动化交易系统集成
- 监控系统集成 (Prometheus)

### 不适用

- 高频交易 (使用 WebSocket)
- 低延迟场景 (< 1ms)

---

## 性能指标

| 指标 | 目标值 |
|------|--------|
| 吞吐量 | 10,000+ req/sec |
| P99 延迟 | < 100ms |
| 内存占用 | < 50MB |
| 并发连接 | 1000+ |

---

## 依赖

```zig
// build.zig.zon
.httpz = .{
    .url = "https://github.com/karlseguin/http.zig/archive/refs/heads/master.tar.gz",
},
```

---

## 未来改进

- [ ] WebSocket 支持
- [ ] GraphQL 支持
- [ ] OpenAPI 规范生成
- [ ] 请求限流
- [ ] API 版本管理

---

*Last updated: 2025-12-28*
