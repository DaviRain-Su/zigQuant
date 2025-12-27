# RiskEngine - Bug 追踪

> 已知问题和修复记录

**最后更新**: 2025-12-27

---

## 当前状态

RiskEngine 模块处于规划阶段，尚未开始实现。此文档将用于追踪实现过程中发现的问题。

---

## 已知 Bug

*目前没有已知 Bug*

---

## 潜在风险

### 风险 #1: 时间同步问题

**状态**: 待评估
**严重性**: Medium

**描述**:
日损失计算依赖系统时间，如果系统时钟被调整可能导致计算错误。

**潜在影响**:
- 日损失统计不准确
- 跨日重置时机错误

**预防措施**:
```zig
// 在检查时间时处理时间回退
fn checkTimeReset(self: *Self) void {
    const now = std.time.timestamp();
    if (now < self.last_day_start) {
        // 时间回退，重置统计
        self.resetDailyStats();
    }
}
```

---

### 风险 #2: 并发访问

**状态**: 待评估
**严重性**: High

**描述**:
多线程同时调用 checkOrder 可能导致订单频率统计不准确。

**潜在影响**:
- 订单频率限制可能被绕过
- 统计数据不一致

**预防措施**:
```zig
// 使用原子操作
order_count: std.atomic.Value(u32),

// 或使用互斥锁
mutex: std.Thread.Mutex,
```

---

### 风险 #3: 价格获取失败

**状态**: 待评估
**严重性**: Medium

**描述**:
市价单没有价格，需要获取最新市场价格进行检查。如果获取失败可能导致检查无法进行。

**潜在影响**:
- 无法检查市价单
- 可能错误拒绝或放行订单

**预防措施**:
```zig
// 使用保守估计
const price = order.price orelse blk: {
    if (self.getLatestPrice(order.symbol)) |p| {
        break :blk p;
    } else {
        // 无法获取价格，拒绝订单
        return reject(.price_unavailable, "Cannot determine order value");
    }
};
```

---

## 已修复的 Bug

*模块尚未实现，暂无已修复的 Bug*

---

## 报告 Bug

请包含以下信息：

1. **标题**: 简短描述问题
2. **严重性**: Critical | High | Medium | Low
3. **复现步骤**:
   ```zig
   // 导致问题的代码
   ```
4. **预期行为**: 应该发生什么
5. **实际行为**: 实际发生了什么
6. **环境信息**:
   - Zig 版本
   - 操作系统
   - zigQuant 版本
