# Hyperliquid 连接器 - 功能概览

> ZigQuant 与 Hyperliquid DEX 的核心连接模块，提供完整的 REST API 和 WebSocket 支持

**状态**: 🚧 开发中
**版本**: v0.2.0
**Story**: [006-hyperliquid-http](../../../stories/v0.2-mvp/006-hyperliquid-http.md) | [007-hyperliquid-ws](../../../stories/v0.2-mvp/007-hyperliquid-ws.md)
**最后更新**: 2025-12-23

---

## 📋 概述

Hyperliquid 连接器是 ZigQuant 与 Hyperliquid DEX 交互的核心模块。Hyperliquid 是一个高性能的 Layer 1 区块链去中心化交易所，支持永续合约交易，具有低延迟（<10ms）和高吞吐量（200,000 订单/秒）的特点。

该模块提供：
- **HTTP 客户端**: 基于 REST API 的市场数据查询和交易操作
- **WebSocket 客户端**: 实时数据流订阅（订单簿、交易、用户事件）
- **Ed25519 签名**: 符合 Hyperliquid 要求的认证机制
- **自动重连**: WebSocket 断线自动重连和订阅恢复
- **速率限制**: 内置速率限制器，避免 API 封禁

### 为什么需要 Hyperliquid 连接器？

作为 ZigQuant 支持的首个交易所（参见 [ADR-002](../../decisions/002-hyperliquid-first-exchange.md)），Hyperliquid 连接器为系统提供：

1. **市场数据访问**: 实时订单簿、交易历史、K 线数据
2. **交易执行**: 下单、撤单、修改订单等操作
3. **账户管理**: 查询余额、仓位、成交记录
4. **事件推送**: WebSocket 实时推送订单和成交事件

### 核心特性

- ✅ **Info API**: 获取市场数据和账户信息（无需认证）
- ✅ **Exchange API**: 执行交易操作（Ed25519 签名认证）
- ✅ **WebSocket 订阅**: 19 种订阅频道（L2 订单簿、交易、用户事件等）
- ✅ **自动重连**: 断线自动重连，重连后自动重新订阅
- ✅ **错误处理**: 完善的错误分类和重试机制
- ✅ **速率限制**: 客户端速率限制器（20 req/s）
- ✅ **测试网支持**: 完整的测试网环境支持

---

## 🚀 快速开始

### 初始化 HTTP 客户端

```zig
const std = @import("std");
const HyperliquidClient = @import("exchange/hyperliquid/http.zig").HyperliquidClient;
const InfoAPI = @import("exchange/hyperliquid/info_api.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 配置客户端（使用测试网）
    const config = HyperliquidClient.HyperliquidConfig{
        .base_url = HyperliquidClient.HyperliquidConfig.DEFAULT_TESTNET_URL,
        .api_key = null,
        .secret_key = std.os.getenv("HYPERLIQUID_SECRET_KEY"),
        .testnet = true,
        .timeout_ms = 10000,
        .max_retries = 3,
    };

    var client = try HyperliquidClient.init(allocator, config, logger);
    defer client.deinit();

    // 获取 ETH 订单簿
    const orderbook = try InfoAPI.getL2Book(&client, "ETH");
    defer allocator.free(orderbook.bids);
    defer allocator.free(orderbook.asks);

    std.debug.print("Best Bid: {} @ {}\n", .{
        orderbook.bids[0].sz.toFloat(),
        orderbook.bids[0].px.toFloat(),
    });
}
```

### 初始化 WebSocket 客户端

```zig
const HyperliquidWS = @import("exchange/hyperliquid/websocket.zig").HyperliquidWS;

const ws_config = HyperliquidWS.HyperliquidWSConfig{
    .ws_url = HyperliquidWS.HyperliquidWSConfig.DEFAULT_TESTNET_WS_URL,
    .reconnect_interval_ms = 1000,
    .max_reconnect_attempts = 5,
    .ping_interval_ms = 30000,
};

var ws = try HyperliquidWS.init(allocator, ws_config, logger);
defer ws.deinit();

// 设置消息回调
ws.on_message = handleMessage;

// 连接
try ws.connect();

// 订阅 ETH 订单簿
try ws.subscribe(.{
    .channel = .l2Book,
    .coin = "ETH",
});

fn handleMessage(msg: Message) void {
    switch (msg) {
        .l2_book => |book| {
            std.debug.print("Order Book Update: {s}\n", .{book.coin});
        },
        else => {},
    }
}
```

---

## 📚 相关文档

- [API 参考](./api.md) - 完整的 HTTP 和 WebSocket API 文档
- [实现细节](./implementation.md) - 内部实现说明（HTTP/WebSocket/签名）
- [测试文档](./testing.md) - 测试覆盖和使用指南
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 🔧 核心 API

### HTTP 客户端

```zig
pub const HyperliquidClient = struct {
    allocator: std.mem.Allocator,
    config: HyperliquidConfig,
    http_client: std.http.Client,
    auth: Auth,
    rate_limiter: RateLimiter,
    logger: Logger,

    pub fn init(
        allocator: std.mem.Allocator,
        config: HyperliquidConfig,
        logger: Logger,
    ) !HyperliquidClient;

    pub fn deinit(self: *HyperliquidClient) void;

    pub fn get(
        self: *HyperliquidClient,
        endpoint: []const u8,
        params: ?std.json.Value,
    ) !std.json.Value;

    pub fn post(
        self: *HyperliquidClient,
        endpoint: []const u8,
        body: std.json.Value,
    ) !std.json.Value;
};
```

### WebSocket 客户端

```zig
pub const HyperliquidWS = struct {
    allocator: std.mem.Allocator,
    config: HyperliquidWSConfig,
    client: ws.Client,
    subscription_manager: SubscriptionManager,
    message_handler: MessageHandler,
    logger: Logger,

    pub fn init(
        allocator: std.mem.Allocator,
        config: HyperliquidWSConfig,
        logger: Logger,
    ) !HyperliquidWS;

    pub fn deinit(self: *HyperliquidWS) void;
    pub fn connect(self: *HyperliquidWS) !void;
    pub fn disconnect(self: *HyperliquidWS) void;
    pub fn subscribe(self: *HyperliquidWS, subscription: Subscription) !void;
    pub fn unsubscribe(self: *HyperliquidWS, subscription: Subscription) !void;
};
```

---

## 📝 最佳实践

### ✅ DO

```zig
// 1. 始终在测试网验证
const config = HyperliquidClient.HyperliquidConfig{
    .base_url = HyperliquidClient.HyperliquidConfig.DEFAULT_TESTNET_URL,
    .testnet = true,
    // ...
};

// 2. 从环境变量读取私钥
const secret_key = std.os.getenv("HYPERLIQUID_SECRET_KEY") orelse {
    return error.NoSecretKey;
};

// 3. 使用速率限制器
var rate_limiter = RateLimiter.init();
while (true) {
    rate_limiter.wait();
    try client.post("/info", body);
}

// 4. 处理 WebSocket 断线
ws.on_disconnect = handleDisconnect;

fn handleDisconnect() void {
    logger.warn("WebSocket disconnected, auto-reconnecting...", .{});
    // HyperliquidWS 会自动重连并重新订阅
}
```

### ❌ DON'T

```zig
// 1. 不要硬编码私钥
// ❌ const secret_key = "0x123...";

// 2. 不要在主网未经测试就执行交易
// ❌ if (!config.testnet) { try placeOrder(...); }

// 3. 不要忽略错误处理
// ❌ const orderbook = try InfoAPI.getL2Book(&client, "ETH");
//    // 没有处理网络错误、超时等

// 4. 不要超过速率限制
// ❌ while (true) {
//        try client.post("/info", body); // 无限制发送请求
//    }
```

---

## 🎯 使用场景

### ✅ 适用

- **量化交易**: 自动化策略执行（下单、撤单、仓位管理）
- **市场数据**: 获取实时订单簿、K 线、交易历史
- **账户监控**: 实时跟踪余额、仓位、成交记录
- **套利交易**: 低延迟 WebSocket 数据流
- **市场分析**: 历史数据查询和分析

### ❌ 不适用

- **高频交易（<1ms 延迟）**: Hyperliquid WebSocket 延迟 ~10ms
- **现货交易**: Hyperliquid 仅支持永续合约
- **中心化交易所集成**: Hyperliquid 是去中心化交易所

---

## 📊 性能指标

| 指标 | 值 |
|------|-----|
| **HTTP 请求延迟** | ~50-200ms（测试网）|
| **WebSocket 延迟** | <10ms |
| **速率限制** | 20 req/s |
| **订阅限制** | 1000 订阅/IP |
| **重连时间** | <3s（通常 1s） |
| **连接稳定性** | >99.5% |

---

## 💡 未来改进

- [ ] 支持异步 HTTP 请求（基于 async/await）
- [ ] 实现连接池复用
- [ ] 支持批量请求（batch API）
- [ ] 添加请求缓存机制
- [ ] 实现更智能的速率限制（令牌桶算法）
- [ ] 支持 HTTP/2
- [ ] 添加请求/响应拦截器
- [ ] 实现请求去重
- [ ] 支持高级订单类型（TP/SL）
- [ ] 添加消息压缩（减少带宽）

---

*Last updated: 2025-12-23*
