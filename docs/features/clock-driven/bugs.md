# Clock-Driven - Bug 追踪

> 已知问题和修复记录

**最后更新**: 2025-12-27

---

## 当前状态

功能处于待开发状态，尚无已知 Bug。

---

## 已知 Bug

*当前无已知 Bug*

---

## 已修复的 Bug

*暂无*

---

## 潜在问题

### 问题 #1: Tick 超时累积

**状态**: 待验证
**严重性**: Medium
**发现日期**: 设计阶段

**描述**:
如果策略 onTick 持续超时，可能导致 tick 延迟累积。

**复现**:
```zig
fn onTickImpl(...) !void {
    // 模拟耗时操作
    std.time.sleep(200_000_000);  // 200ms，超过 100ms tick 间隔
}
```

**预期行为**:
- 应该记录警告
- 应该考虑是否跳过堆积的 tick

**计划解决方案**:
```zig
// 添加 tick 跳过逻辑
if (accumulated_delay > tick_interval * 2) {
    skip_count += 1;
    std.log.warn("Skipping {} ticks due to delay", .{skip_count});
}
```

---

### 问题 #2: 策略动态修改

**状态**: 设计限制
**严重性**: Low
**发现日期**: 设计阶段

**描述**:
在时钟运行期间添加/移除策略可能导致数据竞争。

**当前限制**:
- `addStrategy()` 和 `removeStrategy()` 不是线程安全的
- 必须在 `start()` 前或 `stop()` 后调用

**未来改进**:
考虑添加线程安全的策略管理队列。

---

## 报告 Bug

请包含以下信息：

1. **标题**: 简短描述问题
2. **严重性**: Critical | High | Medium | Low
3. **复现步骤**:
   - 环境信息 (OS, Zig 版本)
   - 最小复现代码
4. **预期行为**: 期望的正确行为
5. **实际行为**: 实际发生的错误

**提交方式**:
- GitHub Issues: https://github.com/DaviRain-Su/zigQuant/issues
- 标签: `bug`, `clock-driven`

---

*Last updated: 2025-12-27*
