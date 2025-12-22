# ADR-002: 选择 Hyperliquid 作为首个支持的交易所

**状态**: ✅ 已接受
**日期**: 2025-01-22
**决策者**: 项目发起人
**相关 Story**: v0.2 MVP Stories

---

## 背景 (Context)

在 ZigQuant 项目的 MVP 阶段，我们需要选择首个集成的交易所来验证框架的交易功能。这个选择将影响：

1. **技术方向**:
   - API 设计模式
   - 数据结构定义
   - 错误处理策略

2. **功能范围**:
   - 支持的交易类型（现货/合约）
   - 订单类型
   - 实时数据流

3. **开发复杂度**:
   - API 文档质量
   - 认证机制
   - WebSocket 稳定性

4. **约束条件**:
   - 需要支持永续合约交易
   - 需要完整的 API 文档
   - 需要稳定的测试环境
   - 优先考虑去中心化方案

---

## 决策 (Decision)

**我们决定选择 Hyperliquid 作为 ZigQuant 首个集成的交易所**

Hyperliquid 是一个高性能的 L1 区块链 DEX，特点：
- 完全链上的永续合约和现货交易
- 高性能订单簿（200k orders/s）
- 单区块确认（one-block finality）
- 透明的链上执行
- 完整的 API 支持（REST + WebSocket）

**实施方式**:
1. 实现 Hyperliquid 的 REST API 客户端（Info + Exchange endpoints）
2. 实现 WebSocket 实时数据流
3. 支持永续合约交易（Perps）
4. 支持现货交易（Spot）
5. 实现链上订单簿同步

**预期效果**:
- 获得去中心化交易所的集成经验
- 验证高性能场景下的框架能力
- 建立可扩展的交易所抽象层

---

## 备选方案 (Alternatives Considered)

### 方案 A: Binance (中心化交易所)

**描述**: 使用 Binance 作为首个集成对象，这是全球最大的加密货币交易所。

**优点**:
- ✅ 流动性极高
- ✅ API 文档完善
- ✅ 丰富的交易对
- ✅ 成熟的测试网
- ✅ 大量参考实现

**缺点**:
- ❌ 中心化风险（账户可能被冻结）
- ❌ KYC 要求严格
- ❌ API 限流严格
- ❌ 地区访问限制
- ❌ 资金托管风险

**为什么不选**: 中心化交易所存在单点故障风险，且 KYC 要求和地区限制会影响用户使用。作为量化框架，我们希望用户拥有更多控制权。

---

### 方案 B: dYdX v4 (链上衍生品交易所)

**描述**: dYdX v4 是基于 Cosmos SDK 构建的去中心化永续合约交易所。

**优点**:
- ✅ 完全去中心化
- ✅ 专注衍生品交易
- ✅ 较高的流动性
- ✅ 成熟的产品

**缺点**:
- ❌ API 文档相对复杂
- ❌ 需要理解 Cosmos 生态
- ❌ 订单簿非完全透明
- ❌ 集成复杂度较高

**为什么不选**: dYdX v4 的技术架构较复杂，集成需要理解 Cosmos 生态，不利于快速 MVP 验证。

---

### 方案 C: Uniswap v3 (DEX AMM)

**描述**: 使用 Uniswap v3 作为现货交易的 DEX 方案。

**优点**:
- ✅ 最大的 DEX 流动性
- ✅ 完全去中心化
- ✅ 广泛的社区支持
- ✅ 成熟的工具链

**缺点**:
- ❌ 不支持永续合约
- ❌ 仅限现货交易
- ❌ Gas 费用较高
- ❌ 滑点较大
- ❌ 不适合高频交易

**为什么不选**: Uniswap 仅支持现货 AMM 交易，不支持永续合约，不满足我们的策略需求。

---

### 方案 D: GMX (去中心化衍生品)

**描述**: GMX 是基于 Arbitrum 的去中心化永续合约交易平台。

**优点**:
- ✅ 支持永续合约
- ✅ 去中心化
- ✅ 较低的 Gas 费用（L2）
- ✅ 良好的流动性

**缺点**:
- ❌ 非订单簿模式（使用预言机定价）
- ❌ 价格更新延迟
- ❌ 不适合做市策略
- ❌ API 支持有限

**为什么不选**: GMX 使用预言机定价而非订单簿，不适合需要精细订单管理的量化策略。

---

## 结果 (Consequences)

### 正面影响
- ✅ **去中心化**: 无需 KYC，用户完全控制资金
- ✅ **高性能**: 200k orders/s 满足高频交易需求
- ✅ **透明性**: 链上订单簿完全透明，便于策略验证
- ✅ **完整功能**: 同时支持现货和永续合约
- ✅ **API 质量**: 文档清晰，REST + WebSocket 支持良好
- ✅ **创新性**: 学习和验证 L1 DEX 的集成方式
- ✅ **无地区限制**: 任何人都可以使用
- ✅ **单区块确认**: 交易延迟低

### 负面影响
- ⚠️ **生态成熟度**: 相比 Binance，生态较新
- ⚠️ **流动性**: 部分交易对流动性可能不如头部 CEX
- ⚠️ **用户基数**: 用户量相比传统 CEX 较少
- ⚠️ **学习成本**: 团队需要学习 L1 区块链交互
- ⚠️ **Gas 费用**: 链上交易需要支付 Gas（虽然很低）

### 风险
- ⚠️ **协议风险**: L1 协议可能存在未知漏洞
  - **缓解**: 使用测试网充分测试，小额资金验证

- ⚠️ **API 稳定性**: 相对新的平台 API 可能有变化
  - **缓解**: 设计抽象层，隔离交易所特定实现

- ⚠️ **流动性波动**: DEX 流动性可能不稳定
  - **缓解**: 实现智能订单路由和滑点保护

- ⚠️ **网络拥堵**: 高负载时性能可能下降
  - **缓解**: 实现重试机制和队列管理

---

## 实施计划 (Implementation)

### Phase 1: 基础 API 集成
1. 研究 Hyperliquid API 文档
2. 实现认证机制（Ed25519 签名）
3. 实现 Info API（市场数据）
4. 实现 Exchange API（交易操作）

### Phase 2: WebSocket 实时数据
1. 实现 WebSocket 连接管理
2. 订阅订单簿数据
3. 订阅交易数据
4. 订阅用户账户更新

### Phase 3: 交易功能
1. 实现下单功能（限价单/市价单）
2. 实现订单查询
3. 实现订单取消
4. 实现仓位管理

### Phase 4: 高级功能
1. 实现 TP/SL 订单
2. 实现订单簿维护
3. 实现账户余额同步
4. 错误处理和重试逻辑

**预计工作量**: 3-4 周

---

## 验证标准 (Validation)

- [ ] 成功连接 Hyperliquid 主网/测试网
- [ ] 能够获取实时市场数据
- [ ] 能够下单并成功成交
- [ ] 能够查询和取消订单
- [ ] 能够追踪仓位和余额
- [ ] WebSocket 连接稳定性 > 99%
- [ ] 订单执行延迟 < 100ms
- [ ] 完整的错误处理
- [ ] 断线重连正常工作
- [ ] 文档完整（API 文档 + 使用示例）

---

## 性能对比

| 交易所 | 类型 | TPS | 延迟 | 流动性 | 去中心化 | 开发友好度 |
|--------|------|-----|------|--------|----------|------------|
| Hyperliquid | L1 DEX | ★★★★★ | ★★★★★ | ★★★☆☆ | ★★★★★ | ★★★★☆ |
| Binance | CEX | ★★★★★ | ★★★★☆ | ★★★★★ | ☆☆☆☆☆ | ★★★★★ |
| dYdX v4 | L1 DEX | ★★★★☆ | ★★★★☆ | ★★★★☆ | ★★★★☆ | ★★★☆☆ |
| GMX | L2 DEX | ★★★☆☆ | ★★★☆☆ | ★★★☆☆ | ★★★★☆ | ★★★☆☆ |
| Uniswap | DEX | ★★☆☆☆ | ★★☆☆☆ | ★★★★★ | ★★★★★ | ★★★★☆ |

---

## 相关资源

- [Hyperliquid 官方文档](https://hyperliquid.gitbook.io/hyperliquid-docs)
- [Hyperliquid API Reference](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api)
- [相关 Story]: `stories/v0.2-mvp/001-hyperliquid-http.md`
- [相关文档]: `docs/features/hyperliquid-connector/`

---

## 备注

### 未来扩展计划

完成 Hyperliquid 集成后，我们计划按以下顺序支持更多交易所：

1. **Binance** (CEX) - 提供高流动性的 CEX 选择
2. **dYdX v4** (L1 DEX) - 另一个成熟的 DEX 衍生品平台
3. **OKX** (CEX) - 亚洲主要交易所
4. **Uniswap v3** (DEX) - 现货 AMM 支持

### 设计原则

在集成 Hyperliquid 时，我们将建立可复用的交易所抽象层：

```zig
pub const Exchange = struct {
    // 通用接口
    pub fn connect() !void;
    pub fn getOrderBook(symbol: []const u8) !OrderBook;
    pub fn placeOrder(order: Order) !OrderId;
    pub fn cancelOrder(order_id: OrderId) !void;
    pub fn getBalance() !Balance;
    // ...
};

// Hyperliquid 特定实现
pub const HyperliquidExchange = struct {
    base: Exchange,
    // Hyperliquid 特定字段
    // ...
};
```

这样可以让后续集成其他交易所更加容易。

---

*Last updated: 2025-01-22*
