# Exchange Router - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-23

---

## [Unreleased]

### Planned for v0.2.0

#### Phase A: 核心类型和接口
- [ ] 实现统一数据类型 (`types.zig`)
  - [ ] TradingPair
  - [ ] Side, OrderType, TimeInForce
  - [ ] OrderRequest, Order, OrderStatus
  - [ ] Ticker, Orderbook, OrderbookLevel
  - [ ] Balance, Position
- [ ] 实现 IExchange 接口 (`interface.zig`)
  - [ ] VTable 定义
  - [ ] 连接管理方法
  - [ ] 市场数据方法
  - [ ] 交易操作方法
  - [ ] 账户查询方法
- [ ] 单元测试
  - [ ] types_test.zig
  - [ ] 覆盖所有边界情况

#### Phase B: Registry 和 Symbol Mapper
- [ ] 实现 ExchangeRegistry (`registry.zig`)
  - [ ] 单交易所注册
  - [ ] 连接管理
  - [ ] 查询接口
- [ ] 实现 SymbolMapper (`symbol_mapper.zig`)
  - [ ] toHyperliquid()
  - [ ] fromHyperliquid()
  - [ ] 错误处理
- [ ] 单元测试
  - [ ] registry_test.zig
  - [ ] symbol_mapper_test.zig

#### Phase C: Hyperliquid Connector 骨架
- [ ] 实现 HyperliquidConnector (`connector.zig`)
  - [ ] VTable 实现（stub）
  - [ ] 基础结构
  - [ ] 符号映射集成
- [ ] Mock Exchange 实现 (`mock/connector.zig`)
  - [ ] 用于测试的 Mock 实现
- [ ] 单元测试
  - [ ] connector_test.zig

#### Phase D: Hyperliquid 完整实现（随 Story 006-007）
- [ ] HTTP 客户端集成 (Story 006)
  - [ ] 调用 Info API
  - [ ] 调用 Exchange API
  - [ ] 签名和认证
- [ ] WebSocket 客户端集成 (Story 007)
  - [ ] 实时数据订阅
- [ ] 完整 Connector 实现
  - [ ] getTicker()
  - [ ] getOrderbook()
  - [ ] createOrder()
  - [ ] cancelOrder()
  - [ ] getBalance()
  - [ ] getPositions()
- [ ] 集成测试
  - [ ] Testnet 连接测试
  - [ ] API 调用测试

#### Phase E: Trading Layer 集成（Story 010-011）
- [ ] OrderManager 使用 Registry
- [ ] PositionTracker 使用 Registry
- [ ] 集成测试

#### Phase F: CLI 集成（Story 012）
- [ ] CLI 使用 Registry
- [ ] 端到端测试

#### 文档
- [x] README.md - 功能概览
- [x] implementation.md - 实现细节
- [x] api.md - API 参考
- [x] testing.md - 测试策略
- [x] bugs.md - Bug 追踪
- [x] changelog.md - 变更日志

---

## [0.2.0] - 计划中

**发布日期**: TBD

**主题**: Exchange Router 抽象层

### Added
- ✨ 统一的交易所接口 (IExchange)
- ✨ 统一的数据类型系统
- ✨ VTable 模式实现多态
- ✨ ExchangeRegistry 交易所注册表
- ✨ SymbolMapper 符号映射器
- ✨ Hyperliquid Connector 实现
- ✨ Mock Exchange 用于测试
- ✨ 完整的单元测试和集成测试

### Design Goals
- 🎯 解耦上层逻辑与具体交易所实现
- 🎯 支持未来多交易所扩展
- 🎯 类型安全的 API
- 🎯 性能优化（VTable 调用 < 1ns）
- 🎯 完善的错误处理

### Breaking Changes
- ⚠️ OrderManager 不再直接使用 HyperliquidClient
- ⚠️ PositionTracker 不再直接使用 HyperliquidClient
- ⚠️ CLI 需要通过 Registry 访问交易所

---

## [0.3.0] - 规划中

**主题**: 多交易所支持

### Planned
- [ ] 支持多个交易所同时注册
  ```zig
  exchanges: std.StringHashMap(IExchange)
  ```
- [ ] Binance Connector 实现
- [ ] OKX Connector 实现
- [ ] 交易所切换和负载均衡
- [ ] 统一的错误重试机制
- [ ] 跨交易所余额聚合

### API Changes
```zig
// 旧 API (v0.2)
const exchange = try registry.getExchange();

// 新 API (v0.3)
const exchange = try registry.getExchange("hyperliquid");
try registry.addExchange("binance", binance_exchange);
```

---

## [0.4.0] - 规划中

**主题**: 智能路由

### Planned
- [ ] ExchangeRouter 智能路由器
- [ ] 订单路由策略
  - [ ] best_price - 选择最优价格
  - [ ] lowest_fee - 选择最低手续费
  - [ ] split - 拆单到多个交易所
- [ ] 聚合订单簿
  ```zig
  pub fn getAggregatedOrderbook(
      router: *ExchangeRouter,
      pair: TradingPair,
  ) !AggregatedOrderbook
  ```
- [ ] 跨交易所套利检测
- [ ] 智能订单执行

---

## [0.5.0] - 规划中

**主题**: 高级功能

### Planned
- [ ] WebSocket 实时数据聚合
- [ ] 延迟监控和统计
- [ ] 自动故障转移
- [ ] 订单簿深度分析
- [ ] 流动性评估
- [ ] 滑点预测

---

## 版本规范

本项目遵循 [语义化版本 2.0.0](https://semver.org/lang/zh-CN/)：

### 版本号格式: MAJOR.MINOR.PATCH

- **MAJOR**: 不兼容的 API 变更
  - 示例: 修改 IExchange 接口签名
  - 示例: 删除或重命名公共方法

- **MINOR**: 向后兼容的功能新增
  - 示例: 添加新的交易所 Connector
  - 示例: IExchange 接口添加新的可选方法

- **PATCH**: 向后兼容的 Bug 修复
  - 示例: 修复符号映射错误
  - 示例: 修复内存泄漏

### 版本前缀

- **Alpha (v0.x.x)**: 早期开发版本，API 可能频繁变更
- **Beta (v1.0.0-beta.x)**: 功能基本完整，API 趋于稳定
- **Stable (v1.0.0+)**: 生产就绪版本

**当前阶段**: Alpha (v0.2.0-dev)

---

## 发布流程

### 1. 开发阶段
- 在 feature 分支开发
- 编写测试
- 更新文档

### 2. 测试阶段
- 运行所有单元测试
- 运行集成测试
- 性能基准测试
- 代码审查

### 3. 准备发布
- 更新 changelog.md
- 更新版本号
- 生成发布说明
- 打标签

### 4. 发布
- 合并到 main 分支
- 推送标签
- 发布 GitHub Release

---

## 版本依赖

### v0.2.0 依赖

| 组件 | 最低版本 | 说明 |
|------|----------|------|
| Zig | 0.13.0 | 编译器 |
| std.http.Client | 标准库 | HTTP 客户端 |
| std.json | 标准库 | JSON 序列化 |
| Decimal | v0.1.0 | 高精度数值 |
| Logger | v0.1.0 | 日志系统 |
| Timestamp | v0.1.0 | 时间戳 |

### 外部依赖（计划）

| 依赖 | 版本 | 用途 | 引入版本 |
|------|------|------|----------|
| zig-clap | latest | CLI 参数解析 | v0.2.0 |
| websocket.zig | latest | WebSocket 客户端 | v0.2.0 |

---

## 迁移指南

### 从直接使用 HyperliquidClient 迁移到 Exchange Router

**v0.1.x (旧代码)**:
```zig
var hl_client = try HyperliquidClient.init(allocator, config, logger);
defer hl_client.deinit();

const mids = try InfoAPI.getAllMids(&hl_client);
```

**v0.2.0 (新代码)**:
```zig
var registry = ExchangeRegistry.init(allocator, logger);
defer registry.deinit();

const exchange = try HyperliquidConnector.create(allocator, config, logger);
try registry.setExchange(exchange, config);
try registry.connectAll();

const ex = try registry.getExchange();
const pair = TradingPair{ .base = "ETH", .quote = "USDC" };
const ticker = try ex.getTicker(pair);
```

**主要变更**:
1. 使用 Registry 管理交易所
2. 使用统一的 TradingPair 类型
3. 通过 IExchange 接口访问
4. 符号自动转换

---

## 贡献者

### v0.2.0 (计划)
- 待实施

---

## 相关文档

- [README](./README.md) - 功能概览
- [实现细节](./implementation.md) - 架构和设计
- [API 参考](./api.md) - 完整 API 文档
- [测试策略](./testing.md) - 测试覆盖
- [Bug 追踪](./bugs.md) - 已知问题

---

## 发布说明模板

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- ✨ 新功能描述

### Changed
- 🔄 变更描述

### Fixed
- 🐛 Bug 修复描述

### Deprecated
- ⚠️ 即将移除的功能

### Removed
- 🗑️ 已移除的功能

### Security
- 🔒 安全更新

### Performance
- ⚡ 性能优化
```

---

*Last updated: 2025-12-23*
