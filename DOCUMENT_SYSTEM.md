# ZigQuant 文档驱动开发系统

> Document-Driven Development (DDD) - 文档即设计，设计即代码

---

## 🎯 核心理念

```
需求模糊
    ↓
Roadmap (版本规划)
    ↓
Stories (具体任务)
    ↓
Docs (功能文档)
    ↓
Code (代码实现)
    ↓
Tests (测试验证)
    ↓
反馈循环
```

**文档是唯一的真相来源** - 代码随文档变化而变化，文档记录了所有的设计决策和演进过程。

---

## 📂 文档系统结构

```
zigquant/
├── .agent/
│   └── constitution.md              # ⭐ Agent 宪法 - 开发原则
│
├── roadmap.md                        # ⭐ 产品路线图 - 版本规划
│
├── stories/                          # ⭐ 需求故事板
│   ├── templates/
│   │   └── story-template.md        # Story 模板
│   ├── v0.1-foundation/
│   │   ├── 001-decimal-type.md      # ✅ 已完成示例
│   │   ├── 002-time-utils.md
│   │   └── ...
│   ├── v0.2-mvp/
│   │   ├── 001-binance-http.md
│   │   └── ...
│   └── ...
│
├── docs/                            # ⭐ 知识库
│   ├── PROJECT_OUTLINE.md           # 项目总览
│   ├── ARCHITECTURE.md              # 系统架构
│   ├── SECURITY.md                  # 安全设计
│   ├── TESTING.md                   # 测试策略
│   ├── DEPLOYMENT.md                # 部署指南
│   ├── PERFORMANCE.md               # 性能优化
│   │
│   ├── features/                    # 功能文档 (从 stories 派生)
│   │   ├── README.md
│   │   ├── templates/
│   │   ├── decimal/
│   │   │   ├── README.md            # 功能概览
│   │   │   ├── implementation.md    # 实现细节
│   │   │   ├── api.md               # API 文档
│   │   │   ├── testing.md           # 测试覆盖
│   │   │   └── bugs.md              # Bug 追踪
│   │   ├── exchange-connectors/
│   │   └── ...
│   │
│   └── decisions/                   # ⭐ 架构决策记录 (ADR)
│       ├── template.md
│       ├── 001-why-zig.md           # ✅ 示例
│       └── ...
│
├── src/                             # 源代码 (由文档驱动)
└── tests/                           # 测试代码
```

---

## 🔄 工作流程

### 1. 制定版本规划

**文件**: `roadmap.md`

```markdown
## v0.2 - MVP
**核心目标**: 能够连接 Hyperliquid，执行一次完整交易

**Stories**:
- [ ] stories/v0.2-mvp/001-hyperliquid-http.md
- [ ] stories/v0.2-mvp/002-orderbook.md
- [ ] ...

**交付物**:
- ✅ 连接 Hyperliquid
- ✅ 下单功能
- ✅ 余额查询
```

**何时更新**:
- 项目启动时创建初始 Roadmap
- 每完成一个版本，规划下一版本
- 每月回顾，调整优先级

---

### 2. 创建 Story

**文件**: `stories/v0.X-name/NNN-feature.md`

使用模板 `stories/templates/story-template.md` 创建：

```bash
cp stories/templates/story-template.md \
   stories/v0.2-mvp/001-binance-http.md
```

**Story 必须包含**:
- 📋 需求描述 (用户故事)
- 🎯 验收标准 (可测试)
- 🔧 技术设计 (架构、数据结构)
- 📝 任务分解 (Phase 1/2/3)
- 🧪 测试策略
- 📚 相关文档链接

**何时创建**:
- 从 Roadmap 派生新任务时
- 发现需要独立实现的功能时

---

### 3. 开发过程

#### 3.1 初始化功能文档

Story 开始时，创建对应的 feature 文档：

```bash
mkdir -p docs/features/hyperliquid-connector
cd docs/features/hyperliquid-connector

# 创建文档文件
touch README.md implementation.md api.md testing.md bugs.md
```

#### 3.2 持续更新

**开发时**:
- 设计阶段 → 更新 `implementation.md`
- 实现代码 → 同步更新 `api.md`
- 发现问题 → 记录到 `bugs.md`

**示例 - bugs.md**:
```markdown
## Bug #1: WebSocket 断线不重连 🚧

**状态**: In Progress
**严重性**: High
**发现**: 2025-01-22

**描述**:
WebSocket 连接断开后，没有自动重连机制。

**复现**:
1. 启动程序
2. 断开网络
3. 恢复网络
4. 观察 - 连接未恢复 ❌

**解决方案**:
实现指数退避重连...

**进度**:
- [x] 分析根因
- [ ] 实现重连逻辑
- [ ] 添加测试
```

---

### 4. 完成 Story

Story 完成时的检查清单：

```markdown
## ✅ 验收检查清单

- [x] 所有验收标准已满足
- [x] 所有任务已完成
- [x] 单元测试通过 (覆盖率 > 85%)
- [x] 文档已更新:
  - [x] docs/features/xxx/README.md
  - [x] docs/features/xxx/implementation.md
  - [x] docs/features/xxx/api.md
  - [x] docs/features/xxx/testing.md
- [x] 无 Critical Bug
- [x] Roadmap 已更新
```

更新 Roadmap:
```markdown
## v0.2 - MVP
**进度**: 40% (2/5 stories 完成)

**Stories**:
- [x] stories/v0.2-mvp/001-binance-http.md ✅
- [x] stories/v0.2-mvp/002-orderbook.md ✅
- [ ] stories/v0.2-mvp/003-order-manager.md 🚧
- [ ] stories/v0.2-mvp/004-cli.md
- [ ] stories/v0.2-mvp/005-integration.md
```

---

### 5. 重大决策记录

当需要做重要的架构决策时，创建 ADR：

**文件**: `docs/decisions/NNN-title.md`

```bash
cp docs/decisions/template.md \
   docs/decisions/002-event-bus-design.md
```

**何时创建 ADR**:
- 选择技术栈
- 架构模式选择
- 重大重构
- 性能优化方案
- 安全策略决定

**ADR 结构**:
```markdown
# ADR-002: 事件总线设计

**状态**: 提议
**日期**: 2025-01-23

## 背景
我们需要一个事件系统来解耦组件...

## 决策
采用发布-订阅模式...

## 备选方案
1. Actor 模型
2. 消息队列
3. 回调函数

## 结果
- ✅ 解耦性好
- ⚠️ 性能开销

## 实施计划
...
```

---

## 📖 文档编写原则

### 1. 清晰 (Clarity)
- 使用简洁的语言
- 避免行话和术语
- 提供代码示例
- 绘制必要的图表

### 2. 完整 (Completeness)
- 包含所有必要信息
- 记录边界条件
- 说明限制和假设

### 3. 可追溯 (Traceability)
- Story → Feature Docs → Code
- 每个功能都能追溯到需求
- 使用相对路径链接

### 4. 及时 (Timeliness)
- 代码变更 = 文档更新
- Bug 修复 = bugs.md 更新
- 不允许"后补文档"

---

## 🛠️ 实用工具

### 快速创建 Story

```bash
#!/bin/bash
# scripts/new-story.sh

VERSION=$1
NAME=$2
ID=$(ls stories/${VERSION}/ | wc -l | xargs printf "%03d")

cp stories/templates/story-template.md \
   stories/${VERSION}/${ID}-${NAME}.md

echo "Created: stories/${VERSION}/${ID}-${NAME}.md"
```

使用:
```bash
./scripts/new-story.sh v0.2-mvp order-manager
# Created: stories/v0.2-mvp/003-order-manager.md
```

### 检查文档完整性

```bash
#!/bin/bash
# scripts/check-docs.sh

for story in stories/**/*.md; do
    if [ "$story" == "stories/templates/story-template.md" ]; then
        continue
    fi

    # 检查是否有对应的 feature 文档
    feature=$(basename $story .md)
    if [ ! -d "docs/features/$feature" ]; then
        echo "⚠️  Missing feature docs for: $story"
    fi
done
```

### 生成文档索引

```bash
#!/bin/bash
# scripts/generate-index.sh

echo "# ZigQuant 文档索引" > DOCS_INDEX.md
echo "" >> DOCS_INDEX.md

echo "## 规划文档" >> DOCS_INDEX.md
echo "- [Roadmap](roadmap.md)" >> DOCS_INDEX.md
echo "" >> DOCS_INDEX.md

echo "## Stories" >> DOCS_INDEX.md
find stories -name "*.md" | grep -v template | sort | while read f; do
    title=$(grep "^# " $f | head -1 | sed 's/# //')
    echo "- [$title]($f)" >> DOCS_INDEX.md
done
```

---

## 🎓 最佳实践

### DO ✅

1. **Story 先行**
   ```
   先写 Story → 再写代码
   ```

2. **小步快跑**
   ```
   每个 Story 应在 1-3 天内完成
   ```

3. **持续更新**
   ```
   代码提交 = 文档提交
   ```

4. **测试驱动**
   ```
   Story 定义验收标准 → 编写测试 → 实现代码
   ```

5. **及时记录 Bug**
   ```
   发现问题立即记录，不要口头传递
   ```

### DON'T ❌

1. **不要跳过文档**
   ```
   "代码就是文档" ❌
   代码只说明 How，不说明 Why
   ```

2. **不要事后补文档**
   ```
   "等功能做完再写文档" ❌
   事后通常不会补，或者补得不准确
   ```

3. **不要复制粘贴**
   ```
   每个 Story 都有独特性，认真填写
   ```

4. **不要忽视 Bug 文档**
   ```
   Bug 修复历史是宝贵的知识
   ```

---

## 📊 文档质量度量

### 覆盖率指标

```bash
# 检查 Story 完成度
total_stories=$(find stories -name "*.md" | grep -v template | wc -l)
completed_stories=$(grep -r "状态.*✅" stories | wc -l)
echo "Story 完成率: $completed_stories / $total_stories"

# 检查功能文档完整性
for feature in src/*/; do
    feature_name=$(basename $feature)
    if [ ! -d "docs/features/$feature_name" ]; then
        echo "⚠️  缺少文档: $feature_name"
    fi
done
```

### 质量检查

- [ ] 每个 feature 有对应文档
- [ ] 所有 Story 状态明确
- [ ] 无超过 7 天的 Open Bug
- [ ] Roadmap 每月更新
- [ ] ADR 记录重大决策

---

## 🔗 相关资源

- [文档驱动开发](https://documentation-driven-development.readthedocs.io/)
- [ADR 最佳实践](https://adr.github.io/)
- [用户故事地图](https://www.jpattonassociates.com/user-story-mapping/)

---

## 💡 启发

> "Documentation is a love letter that you write to your future self."
> -- Damian Conway

文档不是负担，是资产。良好的文档系统会让项目：
- 🎯 **方向清晰** - Roadmap 指引方向
- 📝 **需求明确** - Stories 定义任务
- 📚 **知识积累** - Docs 记录演进
- 🔍 **可追溯** - 链接串联全局
- 🤖 **AI 友好** - 结构化易于理解

---

*Happy Document-Driven Development!* 🚀
