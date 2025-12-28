# zigQuant TODO 清单

> 更新于 2024-12

---

## 架构概览

```
┌─────────────────────────────────────────────────────┐
│                   User Interface                     │
│         (CLI, TUI, Web UI, REST API)                 │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│                  Trading Layer                       │
│  OrderManager, PositionTracker (依赖 IExchange)      │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│              Exchange Abstraction Layer              │
│  IExchange → HyperliquidConnector, (Binance, OKX)   │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│           Market Layer (通用数据结构)                │
│              OrderBook, Ticker, Candle              │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│            Core Layer (通用基础设施)                 │
│         Decimal, Time, Logger, Config               │
└─────────────────────────────────────────────────────┘
```

---

## ✅ 已完成

1. ✅ 交易所连接器 Phase D (connector.zig) - HTTP/WebSocket 客户端初始化
2. ✅ RecoveryManager IExchange 集成 - 交易所同步功能
3. ✅ StopLossManager 订单执行回调 - 止损订单自动执行
4. ✅ RiskEngine Kill Switch 自动平仓 - 紧急平仓功能
5. ✅ BacktestEngine - 事件驱动回测引擎
6. ✅ CLI 策略命令 (backtest, optimize)
7. ✅ 策略框架 (IStrategy, 技术指标库, IndicatorManager)
8. ✅ 3 个内置策略 (双均线、RSI 均值回归、布林带突破)
9. ✅ Hyperliquid 适配器: 存储订单 symbol 用于取消订单
10. ✅ Hyperliquid 适配器: 获取 mark price 用于仓位计算
11. ✅ Hyperliquid 适配器: 计算未实现盈亏
12. ✅ 模拟执行器: 计算未实现盈亏
13. ✅ CLI Run-Strategy 命令 (Paper Trading 模式)
14. ✅ Optimize 命令 JSON 序列化导出
15. ✅ 数据引擎: 从 CSV 文件加载历史数据
16. ✅ 热重载: 发布 config_reloaded 事件
17. ✅ 数据加载器: 支持 ISO 8601 日期格式解析
18. ✅ 数据存储: 计算实际文件大小统计
19. ✅ 市场数据: Decimal NaN 支持用于指标初始化

---

## ⏳ 待完成

### 低优先级 (改进/扩展 - 未来规划)

| 模块 | 文件 | 内容 |
|------|------|------|
| 适配器模块 | adapters/mod.zig | Binance, OKX 交易所适配器 |
| 警报通道 | risk/alert.zig | Telegram, Email, Webhook, Slack, Discord |

---

## 统计

- ✅ 已完成: 19 项
- 🔹 低优先级待完成: 2 项
- **总计待完成: 2 项**

---

## 未来规划

### Story 待完成
- ☐ Story 024: Examples and documentation - 待完善
- ☐ Story 022: GridSearchOptimizer (Optional for v0.3.1)

### AI 策略集成 (v0.4.0+)
- LLM Client 抽象层 (OpenAI, Claude)
- AI Advisor 辅助决策
- Hybrid Strategy 混合决策
