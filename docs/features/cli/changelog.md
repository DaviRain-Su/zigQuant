# CLI 界面 - 变更日志

> 版本历史和更新记录

**最后更新**: 2025-12-23

---

## [Unreleased]

### Planned - v0.2.0

#### Added
- ✨ CLI 框架实现
  - 基于 zig-clap 的命令行参数解析
  - 命令路由系统
  - 配置文件加载支持

- ✨ 核心命令实现
  - `market` 命令：查询市场数据
    - `ticker`: 显示最优买卖价
    - `orderbook`: 显示订单簿
    - `trades`: 显示最近成交
  - `order` 命令：订单操作
    - `buy`: 下限价买单
    - `sell`: 下限价卖单
    - `cancel`: 撤销订单
    - `list`: 列出所有订单
  - `position` 命令：仓位查询
    - `list`: 列出所有仓位
    - `info`: 查询仓位详情
  - `account` 命令：账户信息
    - `info`: 显示账户信息
    - `balance`: 显示资金余额
  - `config` 命令：配置管理
    - `show`: 显示当前配置

- ✨ 交互式 REPL 模式
  - 命令循环和解析
  - 命令执行引擎
  - 帮助系统
  - 退出处理

- ✨ 输出格式化
  - 表格化输出
  - 结构化数据显示
  - 错误信息友好提示

- ✨ 全局选项
  - `--config`: 指定配置文件
  - `--verbose`: 详细输出模式
  - `--help`: 显示帮助信息

#### Changed
无（首次发布）

#### Fixed
无（首次发布）

#### Deprecated
无

#### Removed
无

---

## 未来计划

### v0.3.0 (计划中)

#### Planned
- [ ] 彩色输出支持
  - ANSI 颜色码
  - 自动检测终端能力
  - `--no-color` 选项

- [ ] 命令自动补全
  - Tab 补全命令名
  - Tab 补全参数
  - 智能建议

- [ ] 命令历史功能
  - 上下箭头浏览历史
  - 历史记录持久化
  - 历史搜索

- [ ] 高级输出格式
  - JSON 输出模式（`--json`）
  - CSV 输出模式（`--csv`）
  - 分页输出（`--page`）

- [ ] 脚本批处理模式
  - 从文件读取命令
  - 批量执行
  - 错误处理策略

- [ ] 进度指示器
  - 加载动画
  - 进度条
  - 状态更新

### v0.4.0 (计划中)

#### Planned
- [ ] 命令别名系统
  - 用户自定义别名
  - 预设常用别名
  - 别名管理命令

- [ ] 管道和重定向
  - 命令输出重定向
  - 命令间管道连接
  - 过滤和处理

- [ ] 交互式配置
  - `config init` 初始化配置
  - `config edit` 编辑配置
  - 配置验证

- [ ] 插件系统
  - 自定义命令加载
  - 插件管理
  - 插件市场

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
