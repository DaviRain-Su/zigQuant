# Grid Trading - 网格交易

> 自动化网格交易策略，在价格区间内低买高卖获取利润

**状态**: ✅ 已完成
**版本**: v0.10.0
**最后更新**: 2025-12-28

---

## 📋 概述

Grid Trading（网格交易）是一种经典的量化交易策略，通过在预设的价格区间内设置多个买入和卖出订单，利用价格的波动自动低买高卖，获取网格利润。

### 为什么使用网格交易？

- **震荡市场盈利**: 在横盘震荡行情中持续获利
- **无需预测方向**: 不依赖对市场方向的判断
- **自动化执行**: 7x24 小时自动运行
- **风险可控**: 通过网格参数控制风险敞口

### 核心特性

- ✅ **可配置价格区间**: 设置上下边界价格
- ✅ **灵活网格数量**: 根据波动调整网格密度
- ✅ **自动止盈**: 每格自动设置止盈比例
- ✅ **配置文件支持**: 从 JSON 配置文件加载凭证
- ✅ **风险管理集成**: 与 RiskEngine 深度集成
- ✅ **多模式支持**: Paper / Testnet / Mainnet
- ✅ **实时状态监控**: 订单、仓位、PnL 实时显示

---

## 🚀 快速开始

### CLI 使用

```bash
# Paper Trading (模拟交易 - 默认)
zigquant grid --pair BTC-USDC --upper 100000 --lower 90000 --grids 10

# 使用配置文件 (推荐)
zigquant grid --config config.test.json \
    --pair BTC-USDC --upper 100000 --lower 90000 --grids 10 --testnet

# Testnet 交易 (使用命令行参数)
zigquant grid --pair BTC-USDC --upper 100000 --lower 90000 --grids 10 \
    --testnet --wallet 0x... --key abc123...

# 自定义参数
zigquant grid --pair ETH-USDC --upper 4000 --lower 3500 \
    --grids 20 --size 0.1 --tp 0.3 --max-position 5.0
```

### 配置文件格式

创建 `config.test.json`:

```json
{
  "exchanges": [{
    "name": "hyperliquid",
    "api_key": "0x0C219488E878b66d9e098ED59Ab714c5c29eB0dF",
    "api_secret": "982d7cac35c13196542291328fad2af0226638f2694c1d4fb9d15bcae0ee2af5",
    "testnet": true
  }],
  "trading": {
    "max_position_size": 1000.0,
    "leverage": 1,
    "risk_limit": 0.02
  }
}
```

### 代码使用

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

const GridStrategy = zigQuant.GridStrategy;
const GridConfig = zigQuant.GridStrategyConfig;
const Decimal = zigQuant.Decimal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建网格配置
    const config = GridConfig{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(100000),
        .lower_price = Decimal.fromFloat(90000),
        .grid_count = 10,
        .order_size = Decimal.fromFloat(0.001),
        .take_profit_pct = 0.5,  // 0.5%
        .enable_long = true,
        .enable_short = false,
        .max_position = Decimal.fromFloat(1.0),
    };

    try config.validate();

    // 创建策略实例
    var strategy = try GridStrategy.init(allocator, config);
    defer strategy.deinit();

    // 使用策略...
}
```

---

## 📚 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和用例
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 🔧 CLI 参数说明

### 必需参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `-p, --pair` | 交易对 | `BTC-USDC` |
| `--upper` | 价格上界 | `100000` |
| `--lower` | 价格下界 | `90000` |

### 网格参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-g, --grids` | 10 | 网格数量 |
| `-s, --size` | 0.001 | 每格订单大小 |
| `--tp` | 0.5 | 止盈百分比 (%) |
| `--max-position` | 1.0 | 最大总仓位 |

### 交易模式

| 参数 | 说明 |
|------|------|
| `--paper` | 模拟交易 (默认) |
| `--testnet` | Hyperliquid 测试网 |
| `--live` | Hyperliquid 主网 (**慎用**) |

### 凭证配置

| 参数 | 说明 |
|------|------|
| `--config` | 配置文件路径 |
| `--wallet` | 钱包地址 (0x...) |
| `--key` | 私钥 |

**优先级**: CLI 参数 > 配置文件 > 环境变量

### 风险管理

| 参数 | 说明 |
|------|------|
| `--no-risk` | 禁用风险管理 |

### 其他参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--interval` | 5000 | 检查间隔 (ms) |
| `--duration` | 0 | 运行时长 (分钟)，0=无限 |

---

## 📊 工作原理

```
价格
  ^
100000 ├────────────────────── 上界
       │    [SELL] ← 当价格上涨触发卖出
 98000 ├─────────●───────────
       │
 96000 ├─────────●───────────
       │         ↑ 当前价格
 94000 ├─────────●───────────
       │    [BUY] ← 当价格下跌触发买入
 92000 ├─────────●───────────
       │
 90000 ├────────────────────── 下界
       └──────────────────────→ 时间
```

### 执行流程

1. **初始化**: 将价格区间划分为 N 个等距网格
2. **下单**: 在当前价格以下的网格放置买单
3. **买入成交**: 买单成交后，在成交价 + 止盈% 放置卖单
4. **卖出成交**: 卖单成交后，在原网格位置重新放置买单
5. **循环**: 持续执行步骤 3-4，从价格波动中获利

### 计算公式

```
网格间距 = (上界 - 下界) / 网格数量

第 i 层价格 = 下界 + i × 网格间距

止盈价格 = 买入价格 × (1 + 止盈比例)

单格利润 = 订单大小 × 买入价格 × 止盈比例
```

---

## 🛡️ 风险管理

Grid Trading 与 zigQuant 风险管理模块深度集成:

### 集成的风险检查

- **仓位限制**: 检查订单是否超过 `max_position_size`
- **日损失限制**: 检查是否超过 `risk_limit` 百分比
- **订单频率**: 限制每分钟最大订单数 (60)
- **Kill Switch**: 超过阈值自动停止交易

### 风险统计

运行时显示:
```
═══════════════════════════════════════
         Grid Bot Status
═══════════════════════════════════════
Current Price:    95000.00
Position:         0.003000
Active Buy Orders:  3
Active Sell Orders: 2
Total Trades:     15
Realized PnL:     12.5400
───────────────────────────────────────
Risk Checks:      45
Orders Rejected:  2
Kill Switch:      off
═══════════════════════════════════════
```

### 告警通知

通过 AlertManager 发送:
- 交易成交通知
- 风险限制触发告警
- Kill Switch 激活告警

---

## 📝 最佳实践

### ✅ DO

```bash
# 1. 先用 Paper Trading 测试策略
zigquant grid --pair BTC-USDC --upper 100000 --lower 90000 --paper

# 2. 使用配置文件管理凭证 (不要在命令行暴露私钥)
zigquant grid --config config.test.json --testnet ...

# 3. 设置合理的网格参数
#    - 网格间距 > 手续费成本
#    - 止盈 > 滑点 + 手续费
zigquant grid --grids 10 --tp 0.5 ...

# 4. 使用 testnet 进行实盘验证
zigquant grid --config config.test.json --testnet ...

# 5. 限制最大仓位
zigquant grid --max-position 0.1 ...
```

### ❌ DON'T

```bash
# 1. 不要直接使用 mainnet 未经测试的策略
zigquant grid --live ...  # 危险!

# 2. 不要在命令行暴露私钥
zigquant grid --key abc123... --testnet  # 不安全!

# 3. 不要设置过小的网格间距 (会被手续费吃掉)
zigquant grid --grids 100 --tp 0.1 ...  # 利润太薄

# 4. 不要禁用风险管理
zigquant grid --no-risk --live ...  # 非常危险!

# 5. 不要在趋势市场使用网格
#    网格策略最适合震荡行情
```

---

## 🎯 适用场景

### ✅ 适用

- **横盘震荡市场**: 价格在区间内反复波动
- **高波动资产**: BTC、ETH 等主流币种
- **稳定区间**: 有明确的支撑/阻力位
- **中长期持有**: 可以承受短期浮亏

### ❌ 不适用

- **单边趋势市场**: 价格持续上涨或下跌
- **突破行情**: 价格突破区间边界
- **低波动资产**: 波动不足以覆盖成本
- **短期投机**: 需要快速退出

---

## 📈 性能指标

| 指标 | 目标 | 说明 |
|------|------|------|
| 订单延迟 | < 100ms | 从信号到下单 |
| 状态更新 | 5s | 默认检查间隔 |
| 风控检查 | < 1ms | 每笔订单检查 |
| 内存占用 | < 10MB | 长时间运行稳定 |

---

## 💡 未来改进

- [ ] 支持动态网格调整
- [ ] 基于波动率的自动参数优化
- [ ] 多交易对网格组合
- [ ] 与 AI 顾问集成
- [ ] WebSocket 实时订单状态
- [ ] 历史交易回放分析

---

## 🔗 相关资源

- [Hyperliquid 文档](https://hyperliquid.gitbook.io/)
- [网格交易策略详解](../strategy/README.md)
- [风险引擎文档](../risk-engine/README.md)
- [Paper Trading 文档](../paper-trading/README.md)

---

*Last updated: 2025-12-28*
