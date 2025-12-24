# CLI 界面 - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-24

---

## [Released]

### v0.2.0 - 2025-12-24

#### Added
- ✨ CLI 框架实现
  - 简洁的直接命令模式（无子命令层级）
  - JSON 配置文件支持
  - 命令路由系统

- ✨ 核心命令实现（11 个命令）
  - `help`: 显示帮助信息
  - `price <PAIR>`: 查询交易对价格
  - `book <PAIR> [depth]`: 查询订单簿（默认深度 10）
  - `balance`: 查询账户余额
  - `positions`: 查询持仓
  - `orders [PAIR]`: 查询未成交订单（可按交易对筛选）
  - `buy <PAIR> <QTY> <PRICE>`: 下限价买单
  - `sell <PAIR> <QTY> <PRICE>`: 下限价卖单
  - `cancel <ORDER_ID>`: 撤销指定订单
  - `cancel-all [PAIR]`: 撤销所有订单（可按交易对筛选）
  - `repl`: 进入交互式 REPL 模式

- ✨ 交互式 REPL 模式
  - 命令循环和解析
  - 命令执行引擎
  - 帮助系统
  - 退出处理（`exit` 或 `quit`）

- ✨ 输出格式化
  - ANSI 彩色输出（使用 ConsoleWriter）
  - 结构化数据显示
  - 友好的错误信息提示

- ✨ Exchange 集成
  - 通过 IExchange 接口连接 Hyperliquid
  - 支持 testnet 和 mainnet
  - Ed25519 签名认证
  - 懒加载 Signer（避免启动阻塞）

- ✨ 内存管理
  - GeneralPurposeAllocator 内存泄漏检测
  - 正确的资源清理和释放

#### Changed
- 🔄 Logger 日志系统增强
  - 支持 printf-style 格式化（元组参数）
  - 支持 structured logging（结构体参数）
  - 自动检测参数类型并选择格式化方式

#### Fixed
- 🐛 修复控制台输出缓冲未刷新导致无输出（src/main.zig:65-66）
- 🐛 修复 console_writer 栈变量导致的悬空指针问题（src/cli/cli.zig:24）
- 🐛 修复内存泄漏：config_parsed 和 connector 未释放（src/cli/cli.zig:25-26, 86-89）
- 🐛 修复 balance/positions 命令的 Signer 懒加载问题（src/exchange/hyperliquid/connector.zig:426, 451）
- 🐛 修复 orders 命令未实现（添加 getOpenOrders 到 IExchange）
- 🐛 修复日志格式问题：printf-style vs structured logging（src/core/logger.zig:108-121）
- 🐛 修复 Zig 0.15.2 Writer API 兼容性问题

#### Tested
- ✅ 所有 11 个命令在 Hyperliquid testnet 上测试通过
- ✅ 使用真实 API 凭证验证 balance/positions/orders 功能
- ✅ 内存泄漏检测通过（无泄漏）
- ✅ REPL 模式交互测试通过

#### Deprecated
无

#### Removed
无

---

## 未来计划

### v0.3.0 (计划中)

#### Planned - 短期改进
- [ ] 订单类型扩展
  - 市价单支持
  - 止损单支持
  - 其他订单类型

- [ ] 输出格式增强
  - JSON 输出模式（`--json`）
  - CSV 输出模式（`--csv`）
  - 自定义格式模板

- [ ] REPL 增强
  - 命令历史（上下箭头）
  - 命令自动补全（Tab 键）
  - 智能建议

- [ ] 性能优化
  - 减少启动时间
  - 连接池复用
  - 缓存机制

### v0.4.0 (计划中)

#### Planned - 长期改进
- [ ] 多交易所支持
  - Binance 集成
  - OKX 集成
  - 其他主流交易所

- [ ] WebSocket 实时数据
  - 实时价格订阅
  - 实时订单簿更新
  - 实时成交通知

- [ ] 批处理和脚本
  - 从文件读取命令
  - 批量执行
  - 错误处理策略

- [ ] TUI 界面
  - 使用 termbox 或类似库
  - 多面板布局
  - 实时数据刷新

- [ ] 命令别名系统
  - 用户自定义别名
  - 预设常用别名

- [ ] 插件系统
  - 自定义命令加载
  - 插件管理

---

## 版本规范

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/) 2.0.0 规范：

### 版本号格式

```
MAJOR.MINOR.PATCH
```

- **MAJOR（主版本号）**: 不兼容的 API 变更
- **MINOR（次版本号）**: 向后兼容的功能新增
- **PATCH（修订号）**: 向后兼容的 Bug 修复

### 预发布版本

预发布版本可以在版本号后添加标识：

- `v0.2.0-alpha.1`: Alpha 测试版
- `v0.2.0-beta.1`: Beta 测试版
- `v0.2.0-rc.1`: 候选发布版

---

## 发布流程

### 1. 准备发布

- [ ] 完成所有计划功能
- [ ] 所有测试通过
- [ ] 文档更新完成
- [ ] 更新 CHANGELOG.md

### 2. 版本标记

```bash
# 创建版本标签
git tag -a v0.2.0 -m "Release v0.2.0: CLI Interface"

# 推送标签
git push origin v0.2.0
```

### 3. 构建发布

```bash
# 构建二进制文件
zig build -Doptimize=ReleaseSafe

# 创建发布包
tar -czf zigquant-v0.2.0-linux-x86_64.tar.gz zig-out/bin/zigquant
```

### 4. 发布说明

在 GitHub Release 中发布：

- 版本号：v0.2.0
- 发布标题：CLI Interface
- 发布说明：包含主要功能和变更
- 附件：二进制发布包

### 5. 公告

- 更新项目 README
- 发布博客文章
- 通知用户和贡献者

---

## 变更类型说明

### Added（新增）
添加的新功能或特性

### Changed（变更）
对现有功能的修改

### Deprecated（弃用）
即将移除的功能（在下一个主版本移除）

### Removed（移除）
已经移除的功能

### Fixed（修复）
Bug 修复

### Security（安全）
安全相关的修复

---

## 历史版本

### v0.1.0 - 2025-XX-XX（假设）

#### Added
- 基础框架搭建
- 核心数据结构
- Decimal 类型实现
- Order 类型实现
- 配置系统

---

## 升级指南

### 从 v0.1.0 升级到 v0.2.0

1. **安装新版本**
   ```bash
   # 下载新版本
   curl -L https://github.com/user/zigquant/releases/download/v0.2.0/zigquant-linux-x86_64.tar.gz -o zigquant.tar.gz

   # 解压
   tar -xzf zigquant.tar.gz

   # 安装
   sudo mv zigquant /usr/local/bin/
   ```

2. **配置迁移**
   ```bash
   # 配置文件格式兼容，无需修改
   # 如需更新，请参考新的配置模板
   zigquant config show
   ```

3. **测试新功能**
   ```bash
   # 测试 CLI 功能
   zigquant --help
   zigquant market ticker ETH
   zigquant repl
   ```

---

## 兼容性说明

### 向后兼容性

- ✅ **v0.2.0**: 完全兼容 v0.1.0 的配置文件
- ✅ **v0.2.0**: 完全兼容 v0.1.0 的 API 接口

### 破坏性变更

目前没有破坏性变更。

---

## 贡献者

感谢以下贡献者对 CLI 界面的贡献：

- TBD

---

## 相关资源

- [项目主页](https://github.com/user/zigquant)
- [文档中心](../../README.md)
- [Story 012: CLI 界面](../../stories/v0.2-mvp/012-cli-interface.md)
- [Bug 追踪](./bugs.md)
- [API 参考](./api.md)

---

*保持此文件更新以反映最新的变更*
