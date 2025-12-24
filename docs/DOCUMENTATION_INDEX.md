# ZigQuant 完整文档索引

> 最后更新: 2025-01-22
> 覆盖: v0.1 Foundation + v0.2 MVP

## 文档统计

### 总览

- **总文档数**: 55+ 个文档
- **功能模块**: 11 个主要模块
- **Story 覆盖**: v0.1 Foundation (001-005) + v0.2 MVP (006-012)

### 文档组织

#### V0.1 Foundation - 核心基础设施 (5个模块, 25+ 个文件)

##### Decimal - 高精度数值 (6 个文件)
- `/docs/features/decimal/README.md` - 功能概览
- `/docs/features/decimal/api.md` - 完整 API 参考
- `/docs/features/decimal/implementation.md` - 实现细节
- `/docs/features/decimal/testing.md` - 测试文档
- `/docs/features/decimal/bugs.md` - Bug 追踪
- `/docs/features/decimal/changelog.md` - 变更日志

##### Time - 时间处理 (6 个文件)
- `/docs/features/time/README.md` - 功能概览
- `/docs/features/time/api.md` - API 参考（Timestamp, Duration, KlineInterval）
- `/docs/features/time/implementation.md` - ISO 8601 解析和 K线对齐算法
- `/docs/features/time/testing.md` - 测试覆盖（25+ 测试用例）
- `/docs/features/time/bugs.md` - Bug 追踪
- `/docs/features/time/changelog.md` - 变更日志

##### Logger - 日志系统 (9 个文件)
- `/docs/features/logger/README.md` - 功能概览
- `/docs/features/logger/api.md` - API 参考
- `/docs/features/logger/implementation.md` - 实现细节
- `/docs/features/logger/usage-guide.md` - 使用指南
- `/docs/features/logger/std-log-bridge.md` - 标准库日志桥接
- `/docs/features/logger/comparison.md` - 与其他日志系统对比
- `/docs/features/logger/testing.md` - 测试文档
- `/docs/features/logger/bugs.md` - Bug 追踪
- `/docs/features/logger/changelog.md` - 变更日志

##### Error System - 错误处理 (6 个文件)
- `/docs/features/error-system/README.md` - 功能概览和五大错误分类
- `/docs/features/error-system/api.md` - API 参考（ErrorContext, WrappedError, 重试机制）
- `/docs/features/error-system/implementation.md` - 实现细节
- `/docs/features/error-system/testing.md` - 测试文档
- `/docs/features/error-system/bugs.md` - Bug 追踪
- `/docs/features/error-system/changelog.md` - 变更日志

##### Config - 配置管理 (6 个文件)
- `/docs/features/config/README.md` - 功能概览
- `/docs/features/config/api.md` - API 参考
- `/docs/features/config/implementation.md` - 实现细节
- `/docs/features/config/testing.md` - 测试文档
- `/docs/features/config/bugs.md` - Bug 追踪
- `/docs/features/config/changelog.md` - 变更日志

##### Exchange Router - 交易所抽象层 (6 个文件)
- `/docs/features/exchange-router/README.md` - 功能概览和 IExchange 接口
- `/docs/features/exchange-router/api.md` - API 参考
- `/docs/features/exchange-router/implementation.md` - VTable 模式实现
- `/docs/features/exchange-router/testing.md` - 测试文档
- `/docs/features/exchange-router/bugs.md` - Bug 追踪
- `/docs/features/exchange-router/changelog.md` - 变更日志

#### V0.2 MVP - 交易功能 (6个模块, 21+ 个文件)

##### Hyperliquid 连接器 (7 个文件)
- `/docs/features/hyperliquid-connector/README.md` - 功能概览和快速开始
- `/docs/features/hyperliquid-connector/api-reference.md` - 完整 API 参考
- `/docs/features/hyperliquid-connector/authentication.md` - Ed25519 认证详解
- `/docs/features/hyperliquid-connector/testing.md` - 测试指南（单元 + 集成）
- `/docs/features/hyperliquid-connector/websocket.md` - WebSocket 使用指南
- `/docs/features/hyperliquid-connector/subscriptions.md` - WebSocket 订阅详解
- `/docs/features/hyperliquid-connector/message-types.md` - 消息类型参考

#### 订单簿 (3 个文件)
- `/docs/features/orderbook/README.md` - 订单簿概览
- `/docs/features/orderbook/api-reference.md` - API 参考
- `/docs/features/orderbook/performance.md` - 性能优化指南

#### 订单系统 (3 个文件)
- `/docs/features/order-system/README.md` - 订单系统概览
- `/docs/features/order-system/order-types.md` - 订单类型详解
- `/docs/features/order-system/order-lifecycle.md` - 订单生命周期

#### 订单管理器 (3 个文件)
- `/docs/features/order-manager/README.md` - 订单管理器概览
- `/docs/features/order-manager/api-reference.md` - API 参考
- `/docs/features/order-manager/error-handling.md` - 错误处理指南

#### 仓位追踪器 (2 个文件)
- `/docs/features/position-tracker/README.md` - 仓位追踪器概览
- `/docs/features/position-tracker/pnl-calculation.md` - 盈亏计算详解

#### CLI (3 个文件)
- `/docs/cli/README.md` - CLI 使用指南
- `/docs/cli/commands.md` - 命令参考
- `/docs/cli/examples.md` - 使用示例

#### 索引文档 (1 个文件)
- `/docs/features/README.md` - 功能模块总索引

#### 实践示例 (4 个文件)
- `/examples/README.md` - 示例总览
- `/examples/01_core_basics.zig` - 核心基础（Logger, Decimal, Time, Errors）
- `/examples/02_websocket_stream.zig` - WebSocket 实时数据流
- `/examples/03_http_market_data.zig` - HTTP 市场数据查询
- `/examples/04_exchange_connector.zig` - 交易所抽象层使用

#### 故障排查文档
- `/docs/troubleshooting/README.md` - 故障排查总览
- `/docs/troubleshooting/zig-0.15.2-logger-compatibility.md` - Zig 0.15.2 日志兼容性
- `/docs/troubleshooting/quick-reference-zig-0.15.2.md` - Zig 0.15.2 快速参考
- `/docs/troubleshooting/bufferedwriter-trap.md` - BufferedWriter 陷阱

## 文档结构

```
docs/
├── DOCUMENTATION_INDEX.md (本文件)
├── features/
│   ├── README.md (功能总索引)
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

## 每个模块的关键内容

### V0.1 Foundation Modules

#### 1. Decimal - 高精度数值

**核心内容**:
- 18位小数精度（满足金融交易需求）
- 基于 i128 整数运算（无浮点误差）
- 完整算术运算（加减乘除、比较）
- 字符串解析和格式化
- 零内存分配（除字符串操作）

**Story 来源**:
- [001-decimal.md](../stories/v0.1-foundation/001-decimal.md)

**代码示例**:
- 创建和转换 Decimal
- 算术运算和比较
- 字符串解析和格式化
- 性能基准测试

---

#### 2. Time - 时间处理

**核心内容**:
- Timestamp（毫秒精度 Unix 时间戳）
- Duration（时间间隔）
- KlineInterval（K线周期枚举）
- ISO 8601 解析和格式化
- K线时间对齐算法

**Story 来源**:
- [002-time-utils.md](../stories/v0.1-foundation/002-time-utils.md)

**代码示例**:
- 时间戳创建和转换
- 时间运算和比较
- K线对齐
- ISO 8601 处理

---

#### 3. Error System - 错误处理

**核心内容**:
- 五大错误分类（Network, API, Data, Business, System）
- ErrorContext（错误上下文）
- WrappedError（错误包装）
- 重试机制（固定间隔和指数退避）
- 错误工具函数

**Story 来源**:
- [003-error-system.md](../stories/v0.1-foundation/003-error-system.md)

**代码示例**:
- 错误创建和包装
- 重试机制使用
- 错误处理最佳实践

---

#### 4. Logger - 日志系统

**核心内容**:
- 六级日志（Trace, Debug, Info, Warn, Error, Fatal）
- 多种 Writer（Console, File, JSON）
- 结构化字段支持
- std.log 桥接
- 异步日志（可选）

**Story 来源**:
- [004-logger.md](../stories/v0.1-foundation/004-logger.md)

**代码示例**:
- Logger 创建和配置
- 不同 Writer 使用
- 结构化日志
- 日志级别过滤

---

#### 5. Config - 配置管理

**核心内容**:
- JSON 配置文件
- 类型安全的配置结构
- 环境变量覆盖
- 配置验证
- 默认值处理

**Story 来源**:
- [005-config-system.md](../stories/v0.1-foundation/005-config-system.md)

**代码示例**:
- 加载配置文件
- 环境变量覆盖
- 配置验证

---

#### 6. Exchange Router - 交易所抽象层

**核心内容**:
- IExchange 接口（VTable 模式）
- 统一数据类型（TradingPair, OrderRequest, Ticker, Orderbook）
- ExchangeRegistry（交易所注册表）
- SymbolMapper（符号映射）
- Mock Exchange（测试用）

**Story 来源**:
- [Exchange Router Plan](../../../.claude/plans/sorted-crunching-sonnet.md)

**代码示例**:
- 创建和注册交易所
- 通过接口访问交易所
- 符号映射
- Mock 测试

---

### V0.2 MVP Modules

#### 7. Hyperliquid 连接器

**核心内容**:
- HTTP 和 WebSocket 客户端完整实现
- Ed25519 签名机制详解
- Info API 和 Exchange API 完整参考
- WebSocket 订阅类型和消息格式
- 单元测试和集成测试示例

**Story 来源**: 
- [006-hyperliquid-http.md](../stories/v0.2-mvp/006-hyperliquid-http.md)
- [007-hyperliquid-ws.md](../stories/v0.2-mvp/007-hyperliquid-ws.md)
- [HYPERLIQUID_API_RESEARCH.md](../stories/v0.2-mvp/HYPERLIQUID_API_RESEARCH.md)

**代码示例**:
- 创建 HTTP 客户端
- 获取订单簿和账户状态
- WebSocket 订阅和消息处理
- 下单和撤单流程
- 签名生成和验证

---

### 2. 订单簿

**核心内容**:
- L2 订单簿数据结构
- 快照和增量更新机制
- 查询接口（最优价格、价差、深度）
- WebSocket 集成示例
- 性能优化策略

**Story 来源**: 
- [008-orderbook.md](../stories/v0.2-mvp/008-orderbook.md)

**代码示例**:
- 创建和初始化订单簿
- 应用快照和增量更新
- 查询最优买卖价
- 实时订单簿监控

---

### 3. 订单系统

**核心内容**:
- 订单类型定义（限价单、市价单、Post-only、IOC）
- 订单状态枚举
- 订单生命周期管理
- 订单验证逻辑

**Story 来源**: 
- [009-order-types.md](../stories/v0.2-mvp/009-order-types.md)

**代码示例**:
- 创建不同类型的订单
- 订单状态转换
- 订单验证

---

### 4. 订单管理器

**核心内容**:
- 订单提交和撤单接口
- 订单状态追踪
- WebSocket 事件处理
- 订单历史查询
- 错误处理和重试机制

**Story 来源**: 
- [010-order-manager.md](../stories/v0.2-mvp/010-order-manager.md)

**代码示例**:
- 下单流程
- 批量撤单
- 订单状态查询
- WebSocket 事件处理

---

### 5. 仓位追踪器

**核心内容**:
- 仓位数据结构（基于 Hyperliquid API）
- 账户状态管理
- 盈亏计算（已实现/未实现）
- WebSocket 成交事件处理
- 清算价格和保证金计算

**Story 来源**: 
- [011-position-tracker.md](../stories/v0.2-mvp/011-position-tracker.md)

**代码示例**:
- 同步账户状态
- 处理成交事件
- 计算盈亏
- 查询仓位

---

### 6. CLI

**核心内容**:
- CLI 命令结构
- 市场数据命令（ticker, orderbook）
- 订单命令（buy, sell, cancel）
- 仓位和账户查询
- REPL 交互式模式

**Story 来源**: 
- [012-cli-interface.md](../stories/v0.2-mvp/012-cli-interface.md)

**代码示例**:
- CLI 使用示例
- REPL 模式
- 批处理脚本

---

## 文档使用指南

### 按角色分类

#### 初学者
1. 从 [Features 总索引](./features/README.md) 开始
2. 阅读各模块的 `README.md`
3. 参考快速开始示例

#### 开发者
1. 查看 [API Reference](./features/hyperliquid-connector/api-reference.md)
2. 参考代码示例
3. 查看测试指南

#### 架构师
1. 阅读 Story 文档（技术设计）
2. 查看各模块架构说明
3. 参考性能优化指南

### 按任务分类

#### 集成 Hyperliquid
- [Hyperliquid 连接器](./features/hyperliquid-connector/README.md)
- [认证详解](./features/hyperliquid-connector/authentication.md)
- [测试指南](./features/hyperliquid-connector/testing.md)

#### 实现交易逻辑
- [订单管理器](./features/order-manager/README.md)
- [订单类型](./features/order-system/order-types.md)
- [错误处理](./features/order-manager/error-handling.md)

#### 监控和追踪
- [订单簿](./features/orderbook/README.md)
- [仓位追踪器](./features/position-tracker/README.md)
- [盈亏计算](./features/position-tracker/pnl-calculation.md)

#### 命令行工具
- [CLI 使用指南](./cli/README.md)
- [命令参考](./cli/commands.md)

## 文档与 Story 的对应关系

| Story | 文档目录 | 主要文件 |
|-------|---------|---------|
| 006-hyperliquid-http | `features/hyperliquid-connector/` | README, api-reference, authentication, testing |
| 007-hyperliquid-ws | `features/hyperliquid-connector/` | websocket, subscriptions, message-types |
| 008-orderbook | `features/orderbook/` | README, api-reference, performance |
| 009-order-types | `features/order-system/` | README, order-types, order-lifecycle |
| 010-order-manager | `features/order-manager/` | README, api-reference, error-handling |
| 011-position-tracker | `features/position-tracker/` | README, pnl-calculation |
| 012-cli-interface | `cli/` | README, commands, examples |

## 文档特点

### 1. 完整性
- 涵盖所有 MVP 核心功能
- 每个模块都有概览、API 参考和使用示例
- 从 Story 提取了关键技术设计

### 2. 实用性
- 提供可运行的代码示例
- 包含快速开始指南
- 添加了常见问题解答

### 3. 可维护性
- 清晰的目录结构
- 统一的文档格式
- 相互链接的导航

### 4. Zig 原生
- 所有代码示例使用 Zig
- 符合 Zig 最佳实践
- 利用 Zig 的类型系统和内存管理

## 下一步

### 文档完善
- [ ] 补充更多代码示例
- [ ] 添加架构图和流程图
- [ ] 编写故障排查指南
- [ ] 创建性能基准测试文档

### 代码实现
- [ ] 基于文档实现各模块
- [ ] 编写单元测试和集成测试
- [ ] 性能优化和基准测试
- [ ] 代码审查和重构

### 持续更新
- [ ] 根据实现反馈更新文档
- [ ] 添加实际使用案例
- [ ] 补充最佳实践和设计模式
- [ ] 更新 API 变更和版本兼容性

## 参考资料

### 项目文档
- [Stories (v0.2-mvp)](../stories/v0.2-mvp/)
- [Hyperliquid API Research](../stories/v0.2-mvp/HYPERLIQUID_API_RESEARCH.md)
- [Project Outline](./PROJECT_OUTLINE.md)
- [Architecture](./ARCHITECTURE.md)

### 外部资源
- [Hyperliquid Official Documentation](https://hyperliquid.gitbook.io/hyperliquid-docs/)
- [Hyperliquid Python SDK](https://github.com/hyperliquid-dex/hyperliquid-python-sdk)
- [Zig Language Reference](https://ziglang.org/documentation/master/)

---

**文档生成完成**

总计创建了 **21 个核心功能文档** + **1 个总索引文档**，完整覆盖 ZigQuant v0.2 MVP 的所有主要功能模块。

每个模块都包含：
- 功能概览和快速开始
- 详细的 API 参考
- 实用的代码示例
- 测试和最佳实践
- 与 Story 文档的链接

文档结构清晰，易于导航和维护，为后续开发提供了完整的参考资料。

*Last updated: 2025-12-23*
