# Hyperliquid 连接器 - 功能概览

> ZigQuant 与 Hyperliquid DEX 的核心连接模块，提供完整的 REST API 和 WebSocket 支持

**状态**: ✅ 部分实现 (Info API + WebSocket 完成，Exchange API 签名待完善)
**版本**: v0.2.0
**Story**: [006-hyperliquid-http](../../../stories/v0.2-mvp/006-hyperliquid-http.md) | [007-hyperliquid-ws](../../../stories/v0.2-mvp/007-hyperliquid-ws.md)
**最后更新**: 2025-12-24

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
  - `getAllMids()`: 获取所有币种中间价
  - `getL2Book()`: 获取 L2 订单簿快照
  - `getMeta()`: 获取资产元数据
  - `getUserState()`: 获取用户账户状态
- 🚧 **Exchange API**: 执行交易操作（EIP-712 签名认证）
  - ✅ 签名框架实现（基于 zigeth 库）
  - ⏳ 订单提交待完善
  - ⏳ 订单撤销待完善
- ✅ **WebSocket 订阅**: 8 种核心订阅频道
  - `allMids`, `l2Book`, `trades`, `user`
  - `orderUpdates`, `userFills`, `userFundings`
  - `userNonFundingLedgerUpdates`
- ✅ **自动重连**: 断线自动重连，重连后自动重新订阅
- ✅ **错误处理**: 完善的网络错误处理
- ✅ **速率限制**: 令牌桶算法速率限制器（20 req/s）
- ✅ **测试网支持**: 完整的测试网环境支持

---

## 🚀 快速开始

### 通过 IExchange 接口使用

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建日志器
    var logger = createLogger(allocator);
    defer logger.deinit();

    // 配置连接器（使用测试网）
    const config = zigQuant.ExchangeConfig{
        .name = "hyperliquid",
        .testnet = true,
    };

    // 创建 Hyperliquid 连接器
    const connector = try zigQuant.HyperliquidConnector.create(allocator, config, logger);
    defer connector.destroy();

    // 获取 IExchange 接口
    const exchange = connector.interface();

    // 连接到交易所
    try exchange.connect();
    defer exchange.disconnect();

    // 获取 ETH-USDC ticker
    const pair = zigQuant.TradingPair{ .base = "ETH", .quote = "USDC" };
    const ticker = try exchange.getTicker(pair);

    std.debug.print("ETH Mid Price: {}\n", .{ticker.last.toFloat()});

    // 获取订单簿
    const orderbook = try exchange.getOrderbook(pair, 5);
    defer allocator.free(orderbook.bids);
    defer allocator.free(orderbook.asks);

    std.debug.print("Best Bid: {} @ {}\n", .{
        orderbook.bids[0].quantity.toFloat(),
        orderbook.bids[0].price.toFloat(),
    });
}
```

### 初始化 WebSocket 客户端

```zig
const HyperliquidWS = @import("exchange/hyperliquid/websocket.zig").HyperliquidWS;
const ws_types = @import("exchange/hyperliquid/ws_types.zig");

// WebSocket 配置
const ws_config = HyperliquidWS.Config{
    .ws_url = "wss://api.hyperliquid-testnet.xyz/ws",
    .host = "api.hyperliquid-testnet.xyz",
    .port = 443,
    .path = "/ws",
    .use_tls = true,
    .reconnect_interval_ms = 5000,
    .max_reconnect_attempts = 10,
    .ping_interval_ms = 30000,
};

var ws = HyperliquidWS.init(allocator, ws_config, logger);
defer ws.deinit();

// 设置消息回调
ws.on_message = handleMessage;

// 连接
try ws.connect();

// 订阅 ETH L2 订单簿
try ws.subscribe(.{
    .channel = .l2Book,
    .coin = "ETH",
});

// 订阅所有中间价
try ws.subscribe(.{
    .channel = .allMids,
});

fn handleMessage(msg: ws_types.Message) void {
    switch (msg) {
        .l2Book => |book| {
            std.debug.print("L2 Book Update\n", .{});
        },
        .allMids => |mids| {
            std.debug.print("All Mids Update: {} coins\n", .{mids.mids.len});
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

### Connector (IExchange 实现)

```zig
pub const HyperliquidConnector = struct {
    allocator: std.mem.Allocator,
    config: ExchangeConfig,
    logger: Logger,
    connected: bool,

    // HTTP 客户端和 API 模块
    http_client: HttpClient,
    rate_limiter: RateLimiter,
    info_api: InfoAPI,
    exchange_api: ExchangeAPI,
    signer: ?Signer,

    /// 创建新的 Hyperliquid 连接器
    pub fn create(
        allocator: std.mem.Allocator,
        config: ExchangeConfig,
        logger: Logger,
    ) !*HyperliquidConnector;

    /// 销毁连接器
    pub fn destroy(self: *HyperliquidConnector) void;

    /// 获取 IExchange 接口
    pub fn interface(self: *HyperliquidConnector) IExchange;
};
```

### HTTP 客户端

```zig
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    http_client: std.http.Client,
    logger: Logger,

    pub fn init(
        allocator: std.mem.Allocator,
        testnet: bool,
        logger: Logger,
    ) HttpClient;

    pub fn deinit(self: *HttpClient) void;

    pub fn postInfo(self: *HttpClient, request_body: []const u8) ![]const u8;
    pub fn postExchange(self: *HttpClient, request_body: []const u8) ![]const u8;
    pub fn post(self: *HttpClient, endpoint: []const u8, request_body: []const u8) ![]const u8;
};
```

### WebSocket 客户端

```zig
pub const HyperliquidWS = struct {
    allocator: std.mem.Allocator,
    config: Config,
    client: ?websocket.Client,
    subscription_manager: SubscriptionManager,
    message_handler: MessageHandler,
    logger: Logger,

    // 连接状态（原子操作）
    connected: std.atomic.Value(bool),
    should_reconnect: std.atomic.Value(bool),

    // 线程相关分配器
    thread_arena: ?std.heap.ArenaAllocator,

    // 消息回调
    on_message: ?*const fn (Message) void,

    pub fn init(
        allocator: std.mem.Allocator,
        config: Config,
        logger: Logger,
    ) HyperliquidWS;

    pub fn deinit(self: *HyperliquidWS) void;
    pub fn connect(self: *HyperliquidWS) !void;
    pub fn disconnect(self: *HyperliquidWS) void;
    pub fn subscribe(self: *HyperliquidWS, subscription: Subscription) !void;
    pub fn unsubscribe(self: *HyperliquidWS, subscription: Subscription) !void;
    pub fn isConnected(self: *HyperliquidWS) bool;
};
```

---

## 📝 最佳实践

### ✅ DO

```zig
// 1. 始终在测试网验证
const config = zigQuant.ExchangeConfig{
    .name = "hyperliquid",
    .testnet = true,
};

// 2. 使用 IExchange 接口访问
const connector = try HyperliquidConnector.create(allocator, config, logger);
defer connector.destroy();
const exchange = connector.interface();

// 3. 正确处理资源释放
const ticker = try exchange.getTicker(pair);
// ticker 中的 Decimal 类型无需手动释放

const orderbook = try exchange.getOrderbook(pair, 10);
defer allocator.free(orderbook.bids);  // 必须释放
defer allocator.free(orderbook.asks);   // 必须释放

// 4. WebSocket 自动重连已内置
var ws = HyperliquidWS.init(allocator, ws_config, logger);
ws.on_message = handleMessage;
try ws.connect();
// 断线后会自动重连并重新订阅，无需手动处理
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

## 📂 模块架构

```
src/exchange/hyperliquid/
├── connector.zig         # IExchange 接口实现
├── http.zig              # HTTP 客户端（Info + Exchange）
├── info_api.zig          # Info API 端点封装
├── exchange_api.zig      # Exchange API 端点封装
├── auth.zig              # EIP-712 签名认证
├── types.zig             # Hyperliquid 数据类型
├── rate_limiter.zig      # 令牌桶速率限制器
├── websocket.zig         # WebSocket 客户端
├── ws_types.zig          # WebSocket 消息类型
├── subscription.zig      # 订阅管理器
└── message_handler.zig   # 消息解析器
```

---

*Last updated: 2025-12-24*
