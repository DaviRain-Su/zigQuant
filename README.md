# zigQuant

> 基于 Zig 语言的高性能量化交易框架

[![Zig Version](https://img.shields.io/badge/zig-0.15.2-orange.svg)](https://ziglang.org/)
[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)]()
[![Tests](https://img.shields.io/badge/tests-38%2F38-brightgreen.svg)]()

## 📖 项目文档

### 核心文档
- **[📊 项目进度](./docs/PROGRESS.md)** - 完整的项目进度跟踪和状态 ⭐
- [项目大纲](./docs/PROJECT_OUTLINE.md) - 项目愿景、阶段规划和路线图
- [架构设计](./docs/ARCHITECTURE.md) - 系统架构和设计决策
- [功能补充说明](./docs/FEATURES_SUPPLEMENT.md) - 各模块功能详细说明
- [性能指标](./docs/PERFORMANCE.md) - 性能目标和优化策略
- [安全设计](./docs/SECURITY.md) - 安全架构和最佳实践
- [测试策略](./docs/TESTING.md) - 测试框架和覆盖率
- [部署指南](./docs/DEPLOYMENT.md) - 生产环境部署文档

### 功能文档
- [时间模块](./docs/features/time.md) - 时间戳、K线对齐、时区处理
- [错误系统](./docs/features/error-system.md) - 错误分类、重试策略、错误链
- [日志系统](./docs/features/logger.md) - 结构化日志、多种输出格式
- [配置系统](./docs/features/config.md) - 配置加载、环境变量覆盖、验证

### 🔧 故障排查
- **[故障排查索引](./docs/troubleshooting/README.md)** - 常见问题和解决方案
- **[Zig 0.15.2 兼容性问题详解](./docs/troubleshooting/zig-0.15.2-logger-compatibility.md)** ⭐ - Logger 模块适配经验
- **[Zig 0.15.2 快速参考](./docs/troubleshooting/quick-reference-zig-0.15.2.md)** - API 变更速查表

## 🚀 快速开始

### 环境要求

- Zig 0.15.2 或更高版本
- Linux / macOS / Windows

### 构建项目

```bash
# 克隆仓库
git clone https://github.com/your-username/zigQuant.git
cd zigQuant

# 运行测试
zig build test --summary all

# 运行演示程序
zig build run

# 构建 Release 版本
zig build -Doptimize=ReleaseFast
```

### 运行示例

```bash
# 运行所有模块演示
zig build run

# 查看日志输出（包含中文）
zig build run 2>&1 | less
```

## 📦 已实现模块

### ✅ Phase 0.2: 核心工具模块

#### 时间处理 (`src/core/time.zig`)
- ✅ 高精度时间戳（毫秒级）
- ✅ ISO 8601 格式解析和格式化
- ✅ K线时间对齐（1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w）
- ✅ 时区转换和 UTC 处理
- ✅ Duration 计算

#### 错误处理 (`src/core/errors.zig`)
- ✅ 分类错误系统（Network, API, Data, Business, System, Trading）
- ✅ 错误上下文和链式追踪
- ✅ 重试策略配置（固定延迟、指数退避）
- ✅ 错误分类和可重试性判断

#### 日志系统 (`src/core/logger.zig`)
- ✅ 6 级日志（trace, debug, info, warn, error, fatal）
- ✅ 结构化字段支持
- ✅ 多种输出格式（Console, JSON, File）
- ✅ 线程安全设计
- ✅ 日志级别过滤
- ✅ std.log 桥接支持

#### 配置管理 (`src/core/config.zig`)
- ✅ JSON 配置文件加载
- ✅ 环境变量覆盖（ZIGQUANT_* 前缀）
- ✅ 多交易所配置支持
- ✅ 配置验证和类型安全
- ✅ 敏感信息保护（sanitize）

## 🎯 项目特色

### 高性能
- 零分配日志级别过滤
- 编译时类型检查
- 内联优化和泛型特化
- 最小运行时开销

### 类型安全
- 编译时配置验证
- 强类型错误系统
- 精确的数值类型（避免浮点误差）

### 开发体验
- 完整的中文注释
- 详细的文档和示例
- 全面的测试覆盖（38/38 通过）
- 故障排查指南

## 🧪 测试

```bash
# 运行所有测试
zig build test --summary all

# 运行指定模块测试
zig test src/core/time.zig
zig test src/core/errors.zig
zig test src/core/logger.zig
zig test src/core/config.zig

# 显示测试详情
zig build test -freference-trace=10
```

当前测试状态：**38/38 tests passed** ✅

## 📊 性能指标

| 模块 | 性能目标 | 当前状态 |
|------|---------|---------|
| Logger | < 1μs (级别过滤) | ✅ 零分配 |
| Time | < 100ns (now) | ✅ 直接系统调用 |
| Config | < 1ms (加载) | ✅ 单次解析 |
| Error | < 10ns (创建) | ✅ 栈分配 |

## 🛠️ 技术栈

- **语言:** Zig 0.15.2
- **构建系统:** zig build
- **测试框架:** Zig 内置测试
- **文档:** Markdown + JSX 图表

## 📈 开发进度

- [x] Phase 0.2: 核心工具模块（时间、错误、日志、配置）
- [ ] Phase 0.3: 数据结构（环形缓冲区、订单簿）
- [ ] Phase 1: WebSocket 客户端
- [ ] Phase 2: 交易所连接器（Binance）
- [ ] Phase 3: 策略框架
- [ ] Phase 4: 回测引擎

详见 [项目大纲](./docs/PROJECT_OUTLINE.md)

## 🤝 贡献指南

### 提交代码
1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启 Pull Request

### 报告问题
遇到问题时，请先查阅 [故障排查文档](./docs/troubleshooting/README.md)。

如果是新问题：
1. 在 GitHub Issues 中创建问题
2. 提供详细的错误信息和复现步骤
3. 标注 Zig 版本和操作系统

### 编写文档
发现并解决了新问题？请参考 [故障排查贡献指南](./docs/troubleshooting/README.md#贡献指南)。

## 📄 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

## 🙏 致谢

本项目受以下开源项目启发：
- [Hummingbot](https://github.com/hummingbot/hummingbot) - 做市和套利策略
- [Freqtrade](https://github.com/freqtrade/freqtrade) - 回测和自动交易
- [Zig 标准库](https://github.com/ziglang/zig) - 优秀的语言设计

## 📮 联系方式

- 项目主页: https://github.com/your-username/zigQuant
- 问题反馈: https://github.com/your-username/zigQuant/issues
- 讨论区: https://github.com/your-username/zigQuant/discussions

---

**状态:** 🚧 活跃开发中 | **版本:** 0.2.0-alpha | **更新时间:** 2025-12-23
