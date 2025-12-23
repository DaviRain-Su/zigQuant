📋 Phase 1 (v0.2 - MVP) 正确目标：Hyperliquid DEX

  根据你的 docs/decisions/002-hyperliquid-first-exchange.md 和 roadmap.md：

  🎯 Phase 1 核心目标

  能够连接 Hyperliquid L1 DEX，获取链上行情，执行一次完整的永续合约交易操作

  ✅ 为什么选择 Hyperliquid？

  你的决策理由（来自 ADR-002）：
  - ✅ 去中心化: 无需 KYC，用户完全控制资金
  - ✅ 高性能: 200k orders/s，单区块确认
  - ✅ 透明性: 链上订单簿完全透明
  - ✅ 完整功能: 支持现货 + 永续合约
  - ✅ API 质量: 文档清晰，REST + WebSocket 支持良好
  - ✅ 无地区限制: 任何人都可以使用

  📋 Phase 1 Stories 清单

  根据 roadmap.md，你需要在 stories/v0.2-mvp/ 目录下创建以下 Stories：

  stories/v0.2-mvp/
  ├── 001-hyperliquid-http.md      - Hyperliquid REST API 集成
  ├── 002-hyperliquid-ws.md        - Hyperliquid WebSocket 实时数据
  ├── 003-orderbook.md             - 链上订单簿数据结构
  ├── 004-order-types.md           - 订单类型定义
  ├── 005-order-manager.md         - 订单管理器
  ├── 006-position-tracker.md      - 仓位追踪器
  └── 007-cli-interface.md         - 基础 CLI 界面

  🔧 技术实施计划

  Phase 1.1: Hyperliquid API 基础 (Week 1-2)

  Story 001: Hyperliquid HTTP Client
  - HTTP 客户端实现（基于 Zig std.http）
  - Ed25519 签名认证机制
  - Info API（市场数据）
    - GET /info - 获取市场信息
    - POST /info - 查询订单簿、K线等
  - Exchange API（交易操作）
    - POST /exchange - 下单、撤单
    - 签名验证

  Story 002: Hyperliquid WebSocket
  - WebSocket 连接管理
  - 订阅订单簿数据（L2 orderbook）
  - 订阅交易数据（trades）
  - 订阅用户账户更新（user events）
  - 心跳保活和重连机制

  Phase 1.2: 订单簿和交易 (Week 2-3)

  Story 003: OrderBook 数据结构
  - OrderBook 类型定义
  - Bids/Asks 维护
  - 订单簿更新处理
  - 最优买卖价计算

  Story 004: Order Types
  - 订单类型定义（Market, Limit, TP/SL）
  - 永续合约参数（leverage, reduce_only）
  - 订单验证逻辑

  Story 005: Order Manager
  - 下单接口（placeOrder）
  - 撤单接口（cancelOrder）
  - 订单状态查询
  - 订单历史追踪

  Story 006: Position Tracker
  - 持仓数据结构
  - 实时 PnL 计算
  - Funding Rate 处理
  - 保证金计算

  Phase 1.3: CLI 界面 (Week 3-4)

  Story 007: CLI Interface
  - 基础命令行界面
  - 市场数据查询命令
  - 交易命令（long/short）
  - 账户信息命令

  🚀 MVP 演示场景

  $ zigquant
  ZigQuant v0.2.0 - Hyperliquid MVP
  Connected to Hyperliquid L1 DEX
  Wallet: 0x1234...5678

  > price BTC-USD
  BTC-USD (Perps): $43,250.50
  24h Volume: $1.2B
  Funding Rate: 0.01%
  Chain Confirmations: 1 block

  > balance
  USDC: 10,000.00 (on-chain)
  Positions: None

  > long 0.1 BTC-USD market
  Order submitted to chain: 0xabcd...ef01
  Status: FILLED (on-chain confirmed)
  Entry Price: $43,251.20
  Size: 0.1 BTC
  Margin: $4,325.12 USDC (10x leverage)

  > positions
  BTC-USD: +0.1 BTC
  Entry: $43,251.20
  Mark: $43,280.50
  PnL: +$2.93 (0.07%)
  Funding: Next in 2h 15m

  ---
  📝 建议的第一步

  立即行动：创建 Story 001 - Hyperliquid HTTP Client

  我建议从这个开始，因为它是所有后续功能的基础。

  需要创建的文件:
  stories/v0.2-mvp/001-hyperliquid-http.md

  内容应包括:
  1. Hyperliquid API 认证机制（Ed25519 签名）
  2. Info API 端点实现
  3. Exchange API 端点实现
  4. 错误处理和重试逻辑
  5. 限流器集成

  ---
  🔄 同时需要更新的文件

  我还需要更新 docs/PROGRESS.md 中的 Phase 1 描述，将错误的 "Binance" 改为 "Hyperliquid"。

  是否需要我：
  1. ✅ 更新 docs/PROGRESS.md 的 Phase 1 描述（Binance → Hyperliquid）
  2. ✅ 创建 Story 001: Hyperliquid HTTP Client 的模板
  3. ✅ 创建 stories/v0.2-mvp/ 目录结构

  你想让我从哪一个开始？
