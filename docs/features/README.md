# ZigQuant Features Documentation

> 导航: [首页](../../README.md) / Features

本目录包含 ZigQuant v0.2 MVP 所有核心功能的详细文档。

## 📖 文档结构说明

每个功能模块都遵循统一的文档结构，包含以下标准文件：

- **README.md** - 功能概览、快速开始、核心API
- **implementation.md** - 内部实现细节、算法和数据结构
- **api.md** - 完整的 API 参考文档
- **testing.md** - 测试覆盖和性能基准
- **bugs.md** - 已知问题和修复记录
- **changelog.md** - 版本历史和更新记录

---

## 功能模块

### 1. Hyperliquid 连接器

Hyperliquid DEX 集成模块，提供 HTTP API 和 WebSocket 支持。

- [功能概览](./hyperliquid-connector/README.md)
- [实现细节](./hyperliquid-connector/implementation.md)
- [API 参考](./hyperliquid-connector/api.md)
- [测试文档](./hyperliquid-connector/testing.md)
- [Bug 追踪](./hyperliquid-connector/bugs.md)
- [变更日志](./hyperliquid-connector/changelog.md)

**Story**: [006-hyperliquid-http](../../stories/v0.2-mvp/006-hyperliquid-http.md) | [007-hyperliquid-ws](../../stories/v0.2-mvp/007-hyperliquid-ws.md)

---

### 2. 订单簿

高性能 L2 订单簿实现，支持快照和增量更新。

- [功能概览](./orderbook/README.md)
- [实现细节](./orderbook/implementation.md)
- [API 参考](./orderbook/api.md)
- [测试文档](./orderbook/testing.md)
- [Bug 追踪](./orderbook/bugs.md)
- [变更日志](./orderbook/changelog.md)

**Story**: [008-orderbook](../../stories/v0.2-mvp/008-orderbook.md)

---

### 3. 订单系统

订单类型定义、验证和生命周期管理。

- [功能概览](./order-system/README.md)
- [实现细节](./order-system/implementation.md)
- [API 参考](./order-system/api.md)
- [测试文档](./order-system/testing.md)
- [Bug 追踪](./order-system/bugs.md)
- [变更日志](./order-system/changelog.md)

**Story**: [009-order-types](../../stories/v0.2-mvp/009-order-types.md)

---

### 4. 订单管理器

订单提交、取消、状态追踪和事件处理。

- [功能概览](./order-manager/README.md)
- [实现细节](./order-manager/implementation.md)
- [API 参考](./order-manager/api.md)
- [测试文档](./order-manager/testing.md)
- [Bug 追踪](./order-manager/bugs.md)
- [变更日志](./order-manager/changelog.md)

**Story**: [010-order-manager](../../stories/v0.2-mvp/010-order-manager.md)

---

### 5. 仓位追踪器

实时仓位追踪、盈亏计算和风险指标。

- [功能概览](./position-tracker/README.md)
- [实现细节](./position-tracker/implementation.md)
- [API 参考](./position-tracker/api.md)
- [测试文档](./position-tracker/testing.md)
- [Bug 追踪](./position-tracker/bugs.md)
- [变更日志](./position-tracker/changelog.md)

**Story**: [011-position-tracker](../../stories/v0.2-mvp/011-position-tracker.md)

---

### 6. Exchange Router

多交易所抽象层，提供统一的交易所访问接口。

- [功能概览](./exchange-router/README.md)
- [实现细节](./exchange-router/implementation.md)
- [API 参考](./exchange-router/api.md)
- [测试文档](./exchange-router/testing.md)
- [Bug 追踪](./exchange-router/bugs.md)
- [变更日志](./exchange-router/changelog.md)

**Story**: [Phase 0: Exchange Router 设计](../../.claude/plans/sorted-crunching-sonnet.md)

---

### 7. CLI 界面

命令行界面，提供交互式和脚本化的交易操作。

- [功能概览](./cli/README.md)
- [实现细节](./cli/implementation.md)
- [API 参考](./cli/api.md)
- [测试文档](./cli/testing.md)
- [Bug 追踪](./cli/bugs.md)
- [变更日志](./cli/changelog.md)

**Story**: [012-cli-interface](../../stories/v0.2-mvp/012-cli-interface.md)

---

## 文档结构

```
docs/features/
├── README.md (本文件)
├── templates/                          # 文档模板
│   ├── README.md
│   ├── implementation.md
│   ├── api.md
│   ├── testing.md
│   ├── bugs.md
│   └── changelog.md
├── hyperliquid-connector/              # Hyperliquid 连接器 (6 文件)
│   ├── README.md
│   ├── implementation.md
│   ├── api.md
│   ├── testing.md
│   ├── bugs.md
│   └── changelog.md
├── orderbook/                          # 订单簿 (6 文件)
│   ├── README.md
│   ├── implementation.md
│   ├── api.md
│   ├── testing.md
│   ├── bugs.md
│   └── changelog.md
├── order-system/                       # 订单系统 (6 文件)
│   ├── README.md
│   ├── implementation.md
│   ├── api.md
│   ├── testing.md
│   ├── bugs.md
│   └── changelog.md
├── order-manager/                      # 订单管理器 (6 文件)
│   ├── README.md
│   ├── implementation.md
│   ├── api.md
│   ├── testing.md
│   ├── bugs.md
│   └── changelog.md
├── position-tracker/                   # 仓位追踪器 (6 文件)
│   ├── README.md
│   ├── implementation.md
│   ├── api.md
│   ├── testing.md
│   ├── bugs.md
│   └── changelog.md
├── exchange-router/                    # Exchange Router (6 文件)
│   ├── README.md
│   ├── implementation.md
│   ├── api.md
│   ├── testing.md
│   ├── bugs.md
│   └── changelog.md
└── cli/                                # CLI 界面 (6 文件)
    ├── README.md
    ├── implementation.md
    ├── api.md
    ├── testing.md
    ├── bugs.md
    └── changelog.md
```

---

## 快速导航

### 按功能分类

**市场数据**:
- [订单簿维护](./orderbook/README.md)
- [WebSocket 订阅](./hyperliquid-connector/README.md#websocket-客户端)
- [实时数据流](./hyperliquid-connector/implementation.md#websocket-客户端实现)

**交易操作**:
- [订单提交和取消](./order-manager/README.md)
- [订单类型](./order-system/README.md)
- [订单验证](./order-system/implementation.md#订单验证逻辑)

**账户管理**:
- [仓位追踪](./position-tracker/README.md)
- [盈亏计算](./position-tracker/implementation.md#盈亏计算算法)
- [风险指标](./position-tracker/api.md#仓位数据结构)

**集成**:
- [Exchange Router 抽象层](./exchange-router/README.md)
- [多交易所管理](./exchange-router/api.md#exchangeregistry)
- [统一交易接口](./exchange-router/api.md#iexchange-接口)
- [符号映射](./exchange-router/implementation.md#symbolmapper-实现)
- [HTTP 客户端](./hyperliquid-connector/README.md#http-客户端)
- [WebSocket 客户端](./hyperliquid-connector/README.md#websocket-客户端)
- [Ed25519 签名](./hyperliquid-connector/implementation.md#ed25519-认证实现)

**用户界面**:
- [CLI 命令行界面](./cli/README.md)
- [市场数据查询](./cli/api.md#market-命令)
- [订单操作](./cli/api.md#order-命令)
- [交互式 REPL](./cli/implementation.md#repl-交互式模式)

### 按开发阶段

**初始化**:
1. [创建 Exchange Registry](./exchange-router/README.md#快速开始)
2. [注册交易所连接器](./exchange-router/implementation.md#hyperliquid-connector)
3. [创建 HTTP 客户端](./hyperliquid-connector/README.md#快速开始)
4. [创建 WebSocket 客户端](./hyperliquid-connector/README.md#websocket-客户端)
5. [初始化订单簿](./orderbook/README.md#快速开始)
6. [初始化订单管理器](./order-manager/README.md#快速开始)
7. [初始化仓位追踪器](./position-tracker/README.md#快速开始)

**开发**:
1. [Exchange Router 架构](./exchange-router/implementation.md#架构设计)
2. [IExchange 接口实现](./exchange-router/implementation.md#iexchange-接口实现)
3. [订单提交流程](./order-manager/implementation.md#订单提交流程)
4. [订单簿更新](./orderbook/implementation.md#快照应用)
5. [仓位追踪](./position-tracker/implementation.md#仓位追踪实现)

**测试**:
1. [Exchange Router 测试](./exchange-router/testing.md)
2. [Mock Exchange 实现](./exchange-router/testing.md#mock-exchange)
3. [HTTP 客户端测试](./hyperliquid-connector/testing.md)
4. [订单系统测试](./order-system/testing.md)
5. [订单管理器测试](./order-manager/testing.md)
6. [仓位追踪器测试](./position-tracker/testing.md)
7. [CLI 测试](./cli/testing.md)

---

## 相关资源

- **Templates**: [文档模板](./templates/) - 用于创建新功能文档的标准模板
- **Stories**: [技术设计文档](../../stories/v0.2-mvp/) - 详细的技术设计和任务分解
- **API Research**: [Hyperliquid API 研究](../../stories/v0.2-mvp/HYPERLIQUID_API_RESEARCH.md) - API 完整研究文档
- **Official Docs**: [Hyperliquid 官方文档](https://hyperliquid.gitbook.io/hyperliquid-docs/)

---

## 文档版本

- **v0.2.0**: 初始版本，包含 7 个核心功能模块的完整文档
- **最后更新**: 2025-12-23

---

*所有功能文档遵循统一的模板结构，确保一致性和可维护性*
