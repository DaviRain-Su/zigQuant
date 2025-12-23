# ZigQuant Features Documentation

> 导航: [首页](../../README.md) / Features

本目录包含 ZigQuant v0.2 MVP 所有核心功能的详细文档。

## 功能模块

### 1. Hyperliquid 连接器

Hyperliquid DEX 集成模块，提供 HTTP API 和 WebSocket 支持。

- [功能概览](./hyperliquid-connector/README.md)
- [API 参考](./hyperliquid-connector/api-reference.md)
- [认证详解](./hyperliquid-connector/authentication.md)
- [WebSocket 指南](./hyperliquid-connector/websocket.md)
- [订阅类型](./hyperliquid-connector/subscriptions.md)
- [消息类型](./hyperliquid-connector/message-types.md)
- [测试指南](./hyperliquid-connector/testing.md)

**Story**: [006-hyperliquid-http](../../stories/v0.2-mvp/006-hyperliquid-http.md), [007-hyperliquid-ws](../../stories/v0.2-mvp/007-hyperliquid-ws.md)

---

### 2. 订单簿

高性能 L2 订单簿实现。

- [功能概览](./orderbook/README.md)
- [API 参考](./orderbook/api-reference.md)
- [性能优化](./orderbook/performance.md)

**Story**: [008-orderbook](../../stories/v0.2-mvp/008-orderbook.md)

---

### 3. 订单系统

订单类型定义和生命周期管理。

- [功能概览](./order-system/README.md)
- [订单类型](./order-system/order-types.md)
- [订单生命周期](./order-system/order-lifecycle.md)

**Story**: [009-order-types](../../stories/v0.2-mvp/009-order-types.md)

---

### 4. 订单管理器

订单提交、撤单、状态追踪。

- [功能概览](./order-manager/README.md)
- [API 参考](./order-manager/api-reference.md)
- [错误处理](./order-manager/error-handling.md)

**Story**: [010-order-manager](../../stories/v0.2-mvp/010-order-manager.md)

---

### 5. 仓位追踪器

实时仓位追踪和盈亏计算。

- [功能概览](./position-tracker/README.md)
- [盈亏计算](./position-tracker/pnl-calculation.md)

**Story**: [011-position-tracker](../../stories/v0.2-mvp/011-position-tracker.md)

---

### 6. CLI

命令行界面。

- [使用指南](../cli/README.md)
- [命令参考](../cli/commands.md)
- [使用示例](../cli/examples.md)

**Story**: [012-cli-interface](../../stories/v0.2-mvp/012-cli-interface.md)

---

## 文档结构

```
docs/
├── features/
│   ├── README.md (本文件)
│   ├── hyperliquid-connector/
│   │   ├── README.md
│   │   ├── api-reference.md
│   │   ├── authentication.md
│   │   ├── testing.md
│   │   ├── websocket.md
│   │   ├── subscriptions.md
│   │   └── message-types.md
│   ├── orderbook/
│   │   ├── README.md
│   │   ├── api-reference.md
│   │   └── performance.md
│   ├── order-system/
│   │   ├── README.md
│   │   ├── order-types.md
│   │   └── order-lifecycle.md
│   ├── order-manager/
│   │   ├── README.md
│   │   ├── api-reference.md
│   │   └── error-handling.md
│   └── position-tracker/
│       ├── README.md
│       └── pnl-calculation.md
└── cli/
    ├── README.md
    ├── commands.md
    └── examples.md
```

## 快速导航

### 按功能分类

**市场数据**:
- [订单簿维护](./orderbook/README.md)
- [WebSocket 订阅](./hyperliquid-connector/websocket.md)

**交易操作**:
- [下单和撤单](./order-manager/README.md)
- [订单类型](./order-system/order-types.md)

**账户管理**:
- [仓位追踪](./position-tracker/README.md)
- [盈亏计算](./position-tracker/pnl-calculation.md)

**集成**:
- [Hyperliquid API](./hyperliquid-connector/api-reference.md)
- [认证机制](./hyperliquid-connector/authentication.md)

### 按开发阶段

**初始化**:
1. [创建 HTTP 客户端](./hyperliquid-connector/README.md#快速开始)
2. [创建 WebSocket 客户端](./hyperliquid-connector/websocket.md#快速开始)
3. [初始化订单簿](./orderbook/README.md#快速开始)

**开发**:
1. [下单流程](./order-manager/README.md#使用指南)
2. [订单簿更新](./orderbook/README.md#更新订单簿)
3. [仓位追踪](./position-tracker/README.md#使用指南)

**测试**:
1. [HTTP 客户端测试](./hyperliquid-connector/testing.md)
2. [WebSocket 测试](./hyperliquid-connector/testing.md#websocket-测试)
3. [集成测试](./hyperliquid-connector/testing.md#集成测试)

## 相关资源

- [Stories](../../stories/v0.2-mvp/) - 技术设计文档
- [Hyperliquid API Research](../../stories/v0.2-mvp/HYPERLIQUID_API_RESEARCH.md) - API 研究文档
- [Hyperliquid Official Docs](https://hyperliquid.gitbook.io/hyperliquid-docs/)

---

*Last updated: 2025-12-23*
