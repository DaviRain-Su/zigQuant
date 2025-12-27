# LiveTrading - 更新日志

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 版本历史

### v0.5.0 (计划中)

**发布日期**: 待定
**状态**: 📋 计划中

#### 新增功能

- [ ] LiveTradingEngine 核心实现
  - libxev 事件循环集成
  - WebSocket 连接管理
  - 定时器支持 (心跳/Tick)
  - 信号处理

- [ ] WebSocket 功能
  - 连接/断开管理
  - 自动重连 (指数退避)
  - 心跳机制
  - TLS 支持

- [ ] 交易模式
  - Event-Driven 模式
  - Clock-Driven 模式

- [ ] 组件集成
  - DataEngine 集成
  - ExecutionEngine 集成
  - MessageBus 事件发布

#### 性能目标

- [ ] WebSocket 延迟 < 5ms
- [ ] 消息吞吐量 > 5,000/s
- [ ] CPU 使用率 < 20% (空闲)

#### 已知限制

- 依赖 libxev (Linux io_uring 最佳)
- 单事件循环设计

---

## 计划中的功能

### v0.6.0+ (未来版本)

- 多交易所连接
- 连接负载均衡
- 数据压缩
- WebSocket 连接池
- 更多交易所适配器
  - Binance
  - OKX
  - Bybit

---

## 迁移指南

### 从独立交易脚本迁移到 LiveTradingEngine

v0.4.0 及之前版本需要手动管理连接，v0.5.0 提供统一的 LiveTradingEngine。

#### 之前 (v0.4.0)

```zig
// 手动管理 WebSocket
var ws = try WebSocket.connect("wss://api.hyperliquid.xyz/ws");
defer ws.close();

while (true) {
    const msg = try ws.receive();
    processMessage(msg);

    if (needsHeartbeat()) {
        try ws.sendPing();
    }
}
```

#### 之后 (v0.5.0)

```zig
// 使用 LiveTradingEngine
var engine = try LiveTradingEngine.init(allocator, &bus, &cache, .{
    .ws_endpoints = &.{
        .{ .url = "wss://api.hyperliquid.xyz/ws" },
    },
    .heartbeat_interval_ms = 30000,
    .auto_reconnect = true,
});
defer engine.deinit();

// 订阅事件
try bus.subscribe("market_data.*", strategy.onMarketData);

// 启动 (自动管理连接、心跳、重连)
try engine.start();
```

#### 迁移步骤

1. 初始化 LiveTradingEngine
2. 配置 WebSocket 端点
3. 通过 MessageBus 订阅事件
4. 移除手动连接管理代码
5. 调用 start() 启动引擎

---

## 设计决策

### 为什么选择 libxev？

| 特性 | 说明 |
|------|------|
| **Proactor 模式** | 异步完成通知，适合交易系统 |
| **io_uring** | Linux 最高效 I/O |
| **零运行时分配** | 性能可预测 |
| **Zig 原生** | 无 FFI 开销 |
| **生产验证** | Ghostty 终端使用 |

### 为什么支持两种交易模式？

1. **Event-Driven**: 适合趋势跟踪策略，事件触发执行
2. **Clock-Driven**: 适合做市策略，定时更新报价

两种模式可以组合使用。

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [实现细节](./implementation.md)

---

**版本**: v0.5.0
**状态**: 计划中
