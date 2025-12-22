# Decimal - Bug 追踪

> 已知问题和修复记录

**最后更新**: 2025-01-22

---

## 当前状态

✅ **无 Critical 或 High 优先级 Bug**

---

## 已修复的 Bug

### Bug #1: 除法精度丢失 ✅

**状态**: Resolved
**严重性**: High
**发现日期**: 2025-01-21
**修复日期**: 2025-01-21

**描述**:
除法操作 `1.0 / 3.0` 的结果精度不足。

**复现**:
```zig
const a = try Decimal.fromString("1");
const b = try Decimal.fromString("3");
const result = try a.div(b);
// 期望: 0.333333...
// 实际: 0.333000 (不够精确)
```

**根本原因**:
除法前未扩大被除数，导致精度损失。

**解决方案**:
```zig
// 修复前
const result = @divTrunc(self.value, other.value);

// 修复后
const scaled = @as(i256, self.value) * MULTIPLIER;
const result = @divTrunc(scaled, other.value);
```

**关联提交**: abc123def

---

## 已知限制

### 1. 溢出检测

**状态**: Known Limitation
**严重性**: Medium

**描述**:
当前未实现主动溢出检测，依赖 Zig 的运行时检查。

**影响**:
极大数运算可能导致 panic。

**计划**:
v0.2 实现显式溢出检测。

---

### 2. 浮点转换精度

**状态**: By Design
**严重性**: Low

**描述**:
`fromFloat()` 和 `toFloat()` 可能损失精度。

**建议**:
使用 `fromString()` 创建 Decimal。

---

## 报告 Bug

如发现新问题，请记录：

1. **标题**: 简洁描述问题
2. **状态**: Open | In Progress | Resolved
3. **严重性**: Critical | High | Medium | Low
4. **复现步骤**: 详细的复现代码
5. **预期行为**: 期望的正确结果
6. **实际行为**: 当前的错误结果
7. **环境信息**: Zig 版本、操作系统等

---

## Bug 模板

```markdown
## Bug #X: [标题]

**状态**: Open
**严重性**: [Critical/High/Medium/Low]
**发现日期**: YYYY-MM-DD

**描述**:
[详细描述]

**复现**:
[代码示例]

**预期行为**:
[说明]

**实际行为**:
[说明]

**环境**:
- Zig 版本:
- OS:
```
