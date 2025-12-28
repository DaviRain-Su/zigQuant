# HTTP Server - Bug 追踪

> 已知问题和修复状态

**最后更新**: 2025-12-28

---

## 已知问题

### 开放问题

暂无已知问题 (功能尚未实现)

---

## 已修复问题

暂无修复记录

---

## 问题模板

### 问题报告格式

```markdown
### [BUG-XXX] 问题标题

**严重程度**: 严重 | 一般 | 轻微
**状态**: 开放 | 进行中 | 已修复
**发现日期**: YYYY-MM-DD
**修复日期**: YYYY-MM-DD (如已修复)

**描述**:
[问题描述]

**复现步骤**:
1. 步骤 1
2. 步骤 2
3. ...

**预期行为**:
[预期结果]

**实际行为**:
[实际结果]

**环境**:
- OS: Linux/macOS/Windows
- Zig 版本: 0.15.x
- zigQuant 版本: v1.0.0

**解决方案**:
[修复方案，如已修复]
```

---

## 已知限制

### 当前版本限制

1. **仅支持 HTTP/1.1**
   - 不支持 HTTP/2
   - 计划在 v1.2.0 支持

2. **无 WebSocket 支持**
   - 实时推送需要单独的 WebSocket 服务
   - 计划在 v1.1.0 集成

3. **单节点部署**
   - 不支持水平扩展
   - 需要外部负载均衡器

4. **无请求限流**
   - 依赖外部限流 (如 nginx)
   - 计划在 v1.1.0 内置

---

## 反馈渠道

- GitHub Issues: https://github.com/DaviRain-Su/zigQuant/issues
- 讨论区: https://github.com/DaviRain-Su/zigQuant/discussions

---

*Last updated: 2025-12-28*
