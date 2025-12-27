# Hyperliquid Adapter - 交易所适配器

> Hyperliquid DEX 的数据源和执行客户端适配器

**状态**: 📋 待开始
**版本**: v0.6.0
**Story**: [Story 029](../../stories/v0.6.0/STORY_029_HYPERLIQUID_DATA_PROVIDER.md), [Story 030](../../stories/v0.6.0/STORY_030_HYPERLIQUID_EXECUTION_CLIENT.md)
**最后更新**: 2025-12-27

---

## 概述

Hyperliquid Adapter 是 zigQuant v0.6.0 的核心组件，提供与 Hyperliquid DEX 的完整集成，包括实时市场数据接收和订单执行。通过实现 v0.5.0 定义的 `IDataProvider` 和 `IExecutionClient` 接口，实现与现有架构的无缝集成。

### 核心特性

- **实时数据**: WebSocket 订阅市场数据 (报价、订单簿、成交)
- **订单执行**: REST API 提交/取消订单
- **签名验证**: EIP-712 兼容签名
- **自动重连**: 断线自动恢复订阅
- **状态同步**: 订单状态实时更新

---

## 快速开始

### 数据提供者

```zig
const HyperliquidDataProvider = @import("zigQuant").adapters.HyperliquidDataProvider;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建消息总线和缓存
    var bus = MessageBus.init(allocator);
    defer bus.deinit();

    var cache = Cache.init(allocator, &bus, .{});
    defer cache.deinit();

    // 创建数据提供者
    var provider = try HyperliquidDataProvider.init(allocator, &bus, &cache, .{
        .testnet = false,  // 使用主网
    });
    defer provider.deinit();

    // 启动并订阅
    try provider.start();
    try provider.subscribe("BTC");
    try provider.subscribe("ETH");

    // 数据将通过 MessageBus 发布
}
```

### 执行客户端

```zig
const HyperliquidExecutionClient = @import("zigQuant").adapters.HyperliquidExecutionClient;

pub fn main() !void {
    // ... 初始化 allocator, bus, ws_client ...

    // 创建执行客户端
    var client = try HyperliquidExecutionClient.init(allocator, &bus, ws_client, .{
        .testnet = true,  // 使用测试网
        .private_key = "your_private_key_hex",
    });
    defer client.deinit();

    // 提交订单
    const result = try client.submitOrder(.{
        .symbol = "BTC",
        .side = .buy,
        .order_type = .limit,
        .quantity = Decimal.fromFloat(0.1),
        .price = Decimal.fromFloat(50000),
    });

    std.debug.print("Order submitted: {s}\n", .{result.exchange_order_id});
}
```

---

## 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - WebSocket/REST 实现
- [测试文档](./testing.md) - 测试用例
- [Bug 追踪](./bugs.md) - 已知问题
- [变更日志](./changelog.md) - 版本历史

---

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│                   Hyperliquid Adapter                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐    ┌─────────────────────┐        │
│  │ HyperliquidData     │    │ HyperliquidExecution│        │
│  │ Provider            │    │ Client              │        │
│  │ (IDataProvider)     │    │ (IExecutionClient)  │        │
│  └──────────┬──────────┘    └──────────┬──────────┘        │
│             │                          │                    │
│  ┌──────────▼──────────────────────────▼──────────────┐    │
│  │              Shared WebSocket Connection            │    │
│  └─────────────────────────────────────────────────────┘    │
│             │                          │                    │
│  ┌──────────▼──────────┐    ┌──────────▼──────────┐        │
│  │     MessageBus      │    │       Cache         │        │
│  └─────────────────────┘    └─────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

---

## 支持的功能

### 数据订阅

| 频道 | 说明 | 消息格式 |
|------|------|----------|
| allMids | 所有交易对中间价 | 实时更新 |
| l2Book | 订单簿 (买卖盘) | 增量/快照 |
| trades | 最新成交 | 实时推送 |
| candle | K线数据 | 周期更新 |

### 订单类型

| 类型 | 支持 | 说明 |
|------|------|------|
| Limit | ✅ | 限价单 |
| Market | ✅ | 市价单 |
| Stop | ⏳ | 止损单 (计划中) |
| Take Profit | ⏳ | 止盈单 (计划中) |

---

## 配置选项

### DataProvider 配置

```zig
pub const Config = struct {
    /// WebSocket URL
    ws_url: []const u8 = "wss://api.hyperliquid.xyz/ws",

    /// 使用测试网
    testnet: bool = false,

    /// 重连延迟 (毫秒)
    reconnect_delay_ms: u32 = 1000,

    /// 最大重连次数
    max_reconnect_attempts: u32 = 10,

    /// Ping 间隔 (毫秒)
    ping_interval_ms: u32 = 30000,
};
```

### ExecutionClient 配置

```zig
pub const Config = struct {
    /// REST API URL
    api_url: []const u8 = "https://api.hyperliquid.xyz",

    /// 使用测试网
    testnet: bool = false,

    /// 私钥 (hex 格式)
    private_key: []const u8,

    /// Vault 地址 (可选)
    vault_address: ?[]const u8 = null,
};
```

---

## 性能指标

| 指标 | 目标 | 说明 |
|------|------|------|
| 连接延迟 | < 500ms | WebSocket 握手 |
| 数据延迟 | < 10ms | 消息解析到事件发布 |
| 下单延迟 | < 100ms | REST API 往返 |
| 重连成功率 | > 99% | 自动重连机制 |

---

## 安全注意事项

- 私钥应通过环境变量传入，不要硬编码
- 建议先在测试网验证
- 定期检查账户权限设置
- 监控订单状态同步

---

*Last updated: 2025-12-27*
