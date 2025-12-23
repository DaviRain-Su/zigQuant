# 订单管理器 - Bug 追踪

> 已知问题和修复记录

**最后更新**: 2025-12-23

---

## 当前状态

订单管理器目前处于开发阶段，尚未发现生产级别的 Bug。本文档将持续更新，记录在开发、测试和生产环境中发现的问题。

---

## 已知 Bug

### Bug #1: WebSocket 事件处理时的竞态条件

**状态**: Open
**严重性**: Medium
**发现日期**: 2025-12-23

**描述**:
在高并发场景下，当同时收到 HTTP 响应和 WebSocket 订单更新事件时，可能出现订单状态不一致的竞态条件。具体表现为：
1. HTTP 提交订单返回 `resting` 状态
2. WebSocket 几乎同时收到 `filled` 事件
3. 如果 HTTP 响应处理晚于 WebSocket，订单状态可能被错误地覆盖为 `open`

**复现**:
```zig
// 线程 1: 提交订单
try manager.submitOrder(&order);
// HTTP 响应: order.status = .open

// 线程 2: 几乎同时收到 WebSocket 事件
try manager.handleUserFill(fill_event);
// WebSocket: order.status = .filled

// 如果线程 1 的状态更新晚于线程 2
// 最终状态可能错误地变为 .open
```

**解决方案**:
1. 添加订单版本号或时间戳，确保只应用更新的状态
2. 以 WebSocket 事件为权威状态源，HTTP 响应仅用于初始确认
3. 添加状态转换验证，防止无效的状态回退

**工作进度**:
- [ ] 实现订单版本控制
- [ ] 添加状态转换验证逻辑
- [ ] 编写竞态条件测试用例

---

### Bug #2: 批量取消订单时的部分失败处理

**状态**: Open
**严重性**: Low
**发现日期**: 2025-12-23

**描述**:
在批量取消订单时，如果部分订单取消失败，当前实现没有清晰的错误报告机制。调用者无法知道哪些订单成功取消，哪些失败。

**复现**:
```zig
const orders_to_cancel = [_]*Order{ &order1, &order2, &order3 };
try manager.cancelOrders(&orders_to_cancel);

// 如果 order2 取消失败，调用者无法得知具体情况
// 只能逐个检查订单状态
for (orders_to_cancel) |order| {
    std.debug.print("Status: {s}\n", .{order.status.toString()});
}
```

**解决方案**:
1. 返回详细的批量操作结果，包含每个订单的成功/失败状态
2. 实现 `CancelResult` 结构体：
```zig
pub const CancelResult = struct {
    order: *Order,
    success: bool,
    error_message: ?[]const u8,
};

pub fn cancelOrders(self: *OrderManager, orders: []const *Order) ![]CancelResult {
    // 返回详细结果
}
```

**工作进度**:
- [ ] 设计 `CancelResult` API
- [ ] 实现详细结果返回
- [ ] 更新文档和测试

---

### Bug #3: 内存泄漏：错误消息未释放

**状态**: Open
**严重性**: Low
**发现日期**: 2025-12-23

**描述**:
当订单被拒绝时，`error_message` 字段通过 `allocator.dupe()` 分配内存，但在订单生命周期结束时可能未正确释放。

**复现**:
```zig
// submitOrder 中
.error => |err_msg| {
    order.updateStatus(.rejected);
    order.error_message = try self.allocator.dupe(u8, err_msg);
    // 内存未在 order.deinit() 中释放
    return Error.OrderRejected;
}
```

**解决方案**:
在 `Order.deinit()` 中添加错误消息的清理：
```zig
pub fn deinit(self: *Order) void {
    if (self.error_message) |msg| {
        self.allocator.free(msg);
    }
    // 其他清理...
}
```

**工作进度**:
- [ ] 修改 `Order.deinit()` 实现
- [ ] 添加内存泄漏检测测试
- [ ] 使用 Valgrind 或 Zig 的 leak detector 验证

---

## 已修复的 Bug

目前没有已修复的 Bug 记录。

---

## 报告 Bug

如果发现新的 Bug，请按以下格式记录：

### 标题
简短描述问题

### 信息清单
1. **状态**: Open | In Progress | Resolved
2. **严重性**: Critical | High | Medium | Low
3. **发现日期**: YYYY-MM-DD
4. **描述**: 详细描述 Bug 的现象和影响
5. **复现步骤**: 提供可复现的代码示例
6. **预期行为**: 描述正确的行为应该是什么
7. **实际行为**: 描述当前的错误行为
8. **环境信息**:
   - Zig 版本
   - 操作系统
   - 交易所 API 版本
9. **解决方案**: 提出可能的修复方案
10. **工作进度**: 修复进度的 checklist

---

## Bug 严重性定义

- **Critical**: 导致系统崩溃、数据丢失或重大资金损失
- **High**: 核心功能无法使用，但有临时解决方案
- **Medium**: 功能受限，影响用户体验
- **Low**: 小问题，不影响主要功能

---

## 相关资源

- [实现细节](./implementation.md) - 了解内部实现
- [测试文档](./testing.md) - 测试覆盖和用例
- [Story 010](../../../stories/v0.2-mvp/010-order-manager.md) - 原始需求
