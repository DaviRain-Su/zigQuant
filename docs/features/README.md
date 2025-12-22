# Features 文档结构

> 每个功能模块的完整文档组织

---

## 📂 目录结构

```
docs/features/
├── README.md                    # 本文件
│
├── [feature-name]/              # 功能模块文件夹
│   ├── README.md                # 功能概览
│   ├── implementation.md        # 实现细节
│   ├── api.md                   # API 文档
│   ├── testing.md               # 测试策略
│   ├── bugs.md                  # Bug 追踪
│   └── changelog.md             # 变更日志
│
└── templates/                   # 文档模板
    ├── feature-readme.md
    ├── implementation.md
    └── bugs.md
```

---

## 📝 文档模板说明

### README.md (功能概览)
- **目的**: 快速了解功能是什么
- **内容**:
  - 功能简介
  - 使用示例
  - 相关 Story
  - 相关文件路径

### implementation.md (实现细节)
- **目的**: 深入理解内部实现
- **内容**:
  - 架构设计
  - 数据结构
  - 算法说明
  - 性能考虑
  - 已知限制

### api.md (API 文档)
- **目的**: API 使用手册
- **内容**:
  - 公共接口列表
  - 函数签名
  - 参数说明
  - 返回值
  - 错误类型
  - 代码示例

### testing.md (测试策略)
- **目的**: 测试覆盖情况
- **内容**:
  - 测试场景
  - 覆盖率报告
  - 性能基准
  - 边界条件

### bugs.md (Bug 追踪)
- **目的**: 记录和追踪问题
- **内容**:
  - 已知 Bug 列表
  - 修复进度
  - 复现步骤
  - 解决方案

### changelog.md (变更日志)
- **目的**: 追踪功能演进
- **内容**:
  - 版本历史
  - 新增功能
  - 破坏性变更
  - 弃用警告

---

## 🔄 文档更新流程

```
Story 创建
    ↓
初始化 feature 文档文件夹
    ↓
开发过程中持续更新 implementation.md
    ↓
发现 Bug → 记录到 bugs.md
    ↓
修复 Bug → 更新 bugs.md
    ↓
功能完成 → 完善 README.md 和 api.md
    ↓
测试完成 → 更新 testing.md
    ↓
发布版本 → 更新 changelog.md
```

---

## ✅ 文档质量检查

每个功能文档完成时需确保：

- [ ] README.md 有清晰的使用示例
- [ ] implementation.md 解释了核心设计决策
- [ ] api.md 覆盖了所有公共接口
- [ ] testing.md 记录了测试覆盖率
- [ ] bugs.md 没有未解决的 Critical Bug
- [ ] 所有代码示例可以编译运行
- [ ] 链接都有效
- [ ] 图表清晰易懂

---

## 📚 示例

参考 `docs/features/decimal/` 作为标准示例。

---

*Last updated: 2025-01-22*
