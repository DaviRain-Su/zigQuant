# CLI 界面 - 功能概览

> 命令行界面，用于快速测试交易功能和监控系统状态

**状态**: 📋 计划中
**版本**: v0.2.0
**Story**: [../../stories/v0.2-mvp/012-cli-interface.md](../../stories/v0.2-mvp/012-cli-interface.md)
**最后更新**: 2025-12-23

---

## 📋 概述

CLI 界面是 ZigQuant MVP 阶段的主要用户界面，提供命令行方式访问所有核心交易功能。通过简洁的命令结构和交互式 REPL 模式，开发者可以快速测试策略、查询市场数据、执行交易操作并监控账户状态。

### 为什么需要 CLI 界面？

在 MVP 阶段，CLI 是最快速、最灵活的用户界面选择：

- **快速测试**: 无需图形界面即可测试所有交易功能
- **脚本支持**: 支持批处理和自动化测试脚本
- **开发友好**: 命令行输出便于日志记录和调试
- **轻量级**: 无额外依赖，启动快速
- **灵活性**: 支持单命令模式和交互式 REPL 模式

### 核心特性

- ✅ **命令行解析**: 基于 zig-clap 的参数解析框架
- ✅ **子命令系统**: market、order、position、account、config、repl
- ✅ **交互式 REPL**: 支持多命令会话和命令历史
- ✅ **表格化输出**: 清晰的表格格式显示数据
- ✅ **配置管理**: 支持配置文件加载
- ✅ **彩色输出**: 增强可读性的彩色终端输出
- ✅ **错误处理**: 友好的错误提示和帮助信息

---

## 🚀 快速开始

### 基本使用

#### 查询市场数据

```bash
# 查询 ETH 最优买卖价
$ zigquant market ticker ETH
=== ETH Ticker ===
Best Bid: 10.5 @ 2145.23
Best Ask: 8.2 @ 2145.67
Mid Price: 2145.45

# 查询订单簿（深度 5）
$ zigquant market orderbook BTC 5
=== BTC Order Book (Depth: 5) ===

Asks:
  1.2 @ 50105.5
  0.8 @ 50104.0
  2.5 @ 50103.2
  1.5 @ 50102.8
  3.0 @ 50101.5

Bids:
  2.0 @ 50100.0
  1.5 @ 50099.5
  0.9 @ 50098.2
  2.2 @ 50097.0
  1.8 @ 50096.5
```

#### 订单操作

```bash
# 下限价买单
$ zigquant order buy ETH 0.1 2000.0
Placing BUY order: ETH 0.1 @ 2000.0
Order submitted: CLIENT_1640000000000_12345

# 查询订单列表
$ zigquant order list

# 撤单
$ zigquant order cancel CLIENT_1640000000000_12345
```

#### 查询仓位和账户

```bash
# 查询所有仓位
$ zigquant position list

# 查询账户信息
$ zigquant account info
```

#### 交互式 REPL 模式

```bash
$ zigquant repl
ZigQuant REPL - Type 'help' for commands, 'exit' to quit

zigquant> market ticker ETH
=== ETH Ticker ===
Best Bid: 10.5 @ 2145.23
Best Ask: 8.2 @ 2145.67

zigquant> order buy ETH 0.1 2000.0
Order submitted successfully!

zigquant> position list
Symbol  | Side | Size | Entry Price | PnL
--------|------|------|-------------|-----
ETH     | LONG | 1.0  | 2100.0      | +50.5
BTC     | LONG | 0.1  | 50000.0     | +100.0

zigquant> exit
Goodbye!
```

### 配置文件

```bash
# 使用指定配置文件
$ zigquant --config /path/to/config.toml market ticker ETH

# 详细输出模式
$ zigquant --verbose market orderbook BTC
```

---

## 📚 相关文档

- [API 参考](./api.md) - 完整的命令和 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 🔧 核心 API

### 命令结构

```bash
zigquant [OPTIONS] <COMMAND>

Commands:
  market      市场数据命令
  order       订单命令
  position    仓位命令
  account     账户命令
  config      配置命令
  repl        交互式模式

Options:
  -c, --config <PATH>   配置文件路径
  -v, --verbose         详细输出
  -h, --help            显示帮助
```

### Market 命令

```bash
zigquant market <SUBCOMMAND>

Subcommands:
  ticker <SYMBOL>             显示最优买卖价
  orderbook <SYMBOL> [DEPTH]  显示订单簿
  trades <SYMBOL> [LIMIT]     显示最近成交
```

### Order 命令

```bash
zigquant order <SUBCOMMAND>

Subcommands:
  buy <SYMBOL> <QTY> <PRICE>      下限价买单
  sell <SYMBOL> <QTY> <PRICE>     下限价卖单
  cancel <ORDER_ID>               撤单
  list                            列出所有订单
```

### Position 命令

```bash
zigquant position <SUBCOMMAND>

Subcommands:
  list            列出所有仓位
  info <SYMBOL>   查询指定仓位详情
```

### Account 命令

```bash
zigquant account <SUBCOMMAND>

Subcommands:
  info            显示账户信息
  balance         显示资金余额
```

---

## 📝 最佳实践

### ✅ DO

```bash
# 使用配置文件管理连接信息
$ zigquant --config config.toml market ticker ETH

# 在脚本中使用单命令模式
$ ./trading_script.sh
#!/bin/bash
zigquant market ticker ETH > market_data.txt
zigquant position list > positions.txt

# 使用 REPL 进行交互式测试
$ zigquant repl
```

### ❌ DON'T

```bash
# 不要在命令行硬编码敏感信息
$ zigquant --api-key "secret123" order buy ETH 1.0 2000.0  # 错误！

# 不要在生产环境使用 verbose 模式（性能影响）
$ zigquant --verbose order buy ETH 1.0 2000.0  # 仅用于调试

# 不要在自动化脚本中使用 REPL 模式
$ echo "market ticker ETH" | zigquant repl  # 使用单命令模式
```

---

## 🎯 使用场景

### ✅ 适用

- **开发测试**: 快速验证交易逻辑和市场数据获取
- **策略调试**: 交互式执行订单和查询状态
- **自动化脚本**: 批处理和定时任务
- **监控告警**: 定期查询账户和仓位状态
- **日志记录**: 输出可重定向至文件进行分析

### ❌ 不适用

- **生产交易**: 需要更稳定的 API 或 GUI 界面
- **实时监控**: CLI 输出不适合持续刷新的实时数据
- **图表可视化**: 需要专门的图表工具
- **复杂界面**: 需要多窗口、多面板的复杂操作

---

## 📊 性能指标

- **启动时间**: < 100ms
- **命令响应**: < 50ms（不含网络请求）
- **内存占用**: < 10MB
- **REPL 延迟**: < 10ms（命令解析）

---

## 💡 未来改进

- [ ] 支持彩色输出（使用 ANSI 转义码）
- [ ] 实现命令自动补全（Tab 键）
- [ ] 添加命令历史（上下箭头）
- [ ] 支持脚本批处理模式（读取命令文件）
- [ ] 添加进度条和加载动画
- [ ] 支持 JSON 输出格式（便于脚本解析）
- [ ] 实现命令别名系统
- [ ] 添加管道和重定向支持

---

*Last updated: 2025-12-23*
