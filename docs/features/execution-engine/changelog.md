# ExecutionEngine - 更新日志

**版本**: v0.5.0
**状态**: 计划中
**最后更新**: 2025-12-27

---

## 版本历史

### v0.5.0 (计划中)

**发布日期**: 待定
**状态**: 📋 计划中

#### 新增功能

- [ ] ExecutionEngine 核心实现
  - 订单前置追踪
  - 订单提交/取消/修改
  - 订单状态管理

- [ ] 订单前置追踪模式
  - Pending → Tracked 状态流转
  - 零订单丢失设计
  - 自动状态同步

- [ ] 订单恢复功能
  - 系统重启恢复
  - 交易所状态同步
  - 过期订单清理

- [ ] MessageBus 集成
  - 请求端点注册
  - 订单事件发布
  - WebSocket 事件处理

- [ ] 重试和超时
  - 可配置重试次数
  - 指数退避策略
  - 超时处理

#### 性能目标

- [ ] 订单吞吐量 > 10,000/sec
- [ ] 订单延迟 < 10ms
- [ ] 恢复时间 < 1s

#### 已知限制

- 依赖交易所 API 可用性
- 单线程设计（v0.5.0 范围）

---

## 计划中的功能

### v0.6.0+ (未来版本)

- 多交易所支持
- 智能订单路由
- 订单持久化
- 高级订单类型
  - 冰山订单
  - TWAP/VWAP
  - 条件订单
- 风险控制集成

---

## 迁移指南

### 从直接 API 调用迁移到 ExecutionEngine

v0.4.0 及之前版本直接调用交易所 API，v0.5.0 通过 ExecutionEngine 管理。

#### 之前 (v0.4.0)

```zig
// 直接调用交易所 API
const result = try exchange.submitOrder(.{
    .instrument_id = "BTC-USDT",
    .side = .buy,
    .quantity = 1.0,
});

if (result.success) {
    orders.put(result.order_id, order);
}
```

#### 之后 (v0.5.0)

```zig
// 通过 ExecutionEngine (自动追踪)
try execution_engine.submitOrder(.{
    .instrument_id = "BTC-USDT",
    .side = .buy,
    .quantity = 1.0,
});

// 或通过 MessageBus
const response = try message_bus.request("order.submit", .{
    .submit_order = .{
        .instrument_id = "BTC-USDT",
        .side = .buy,
        .quantity = 1.0,
    },
});
```

#### 迁移步骤

1. 初始化 ExecutionEngine 并连接 MessageBus
2. 替换直接 API 调用为 ExecutionEngine 方法
3. 订阅订单事件更新 UI/日志
4. 实现 recoverOrders 调用（启动时）
5. 移除自定义订单追踪代码

---

## 设计决策

### 为什么采用订单前置追踪？

**问题**: 传统模式中，API 调用失败后订单状态不确定。

**解决方案**:
1. 提交前先本地追踪 (pending)
2. API 调用失败不丢失订单
3. WebSocket 确认后更新状态
4. 超时未确认主动查询

**参考**: Hummingbot 订单追踪设计

---

## 相关文档

- [功能概览](./README.md)
- [API 参考](./api.md)
- [实现细节](./implementation.md)

---

**版本**: v0.5.0
**状态**: 计划中
