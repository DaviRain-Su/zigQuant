# 订单系统 - Bug 追踪

> 已知问题和修复记录

**最后更新**: 2025-12-23

---

## 当前状态

订单系统当前处于开发阶段（v0.2.0），暂无已知 Bug。本文档将持续更新，记录开发和测试过程中发现的问题。

---

## 已知 Bug

暂无已知 Bug。

---

## 已修复的 Bug

暂无历史记录。

---

## 潜在问题和改进点

### 问题 #1: 部分成交状态缺失

**状态**: 待讨论
**严重性**: Medium
**发现日期**: 2025-12-23

**描述**:
当前订单状态枚举中没有明确的 `partially_filled` 状态。在 `updateFill` 方法中，部分成交的订单状态处理不够清晰。

根据 Hyperliquid API，订单状态包括: `open`, `filled`, `canceled`, `triggered`, `rejected`, `marginCanceled`，没有显式的部分成交状态。部分成交的订单应该保持 `open` 状态。

**当前实现**:
```zig
pub fn updateFill(...) void {
    // ...
    if (self.remaining_quantity.isZero()) {
        self.updateStatus(.filled);
    } else {
        // 当前只更新时间戳，状态保持不变
        self.updated_at = Timestamp.now();
    }
}
```

**建议**:
- 保持当前实现（与 Hyperliquid API 一致）
- 在文档中明确说明部分成交时订单保持 `open` 状态
- 可通过 `filled_quantity` 和 `remaining_quantity` 判断成交进度

---

### 问题 #2: 订单 ID 生成策略

**状态**: 待讨论
**严重性**: Low
**发现日期**: 2025-12-23

**描述**:
当前客户端订单 ID 使用 `timestamp + random` 生成，这在高频场景下可能产生冲突。

**当前实现**:
```zig
fn generateClientOrderId(allocator: std.mem.Allocator) ![]u8 {
    const timestamp = std.time.milliTimestamp();
    const random = std.crypto.random.int(u32);
    return std.fmt.allocPrint(
        allocator,
        "CLIENT_{d}_{d}",
        .{ timestamp, random }
    );
}
```

**问题场景**:
- 在同一毫秒内创建多个订单
- random u32 可能重复（概率极低）

**建议改进**:
1. 使用递增计数器 + 时间戳
2. 使用 UUID v4
3. 添加机器 ID/进程 ID 前缀

---

### 问题 #3: Decimal 运算异常处理

**状态**: 已处理
**严重性**: Low
**发现日期**: 2025-12-23

**描述**:
在计算平均成交价时，Decimal 除法可能失败（如溢出）。

**当前实现**:
```zig
self.avg_fill_price = total_cost.add(new_cost)
    .div(self.filled_quantity) catch null;
```

**处理方式**:
使用 `catch null` 忽略错误，将平均成交价设为 null。这是合理的降级策略，但应该：
- 记录警告日志
- 在文档中说明此行为

---

### 问题 #4: 触发单验证不完整

**状态**: 待改进
**严重性**: Medium
**发现日期**: 2025-12-23

**描述**:
当前 `validate()` 函数对触发单的验证较为简单，未充分检查触发单特有的参数。

**当前实现**:
```zig
pub fn validate(self: *const Order) !void {
    // ... 基本验证

    // 触发单应该验证:
    // - trigger_price 必须存在
    // - trigger_price 必须为正
    // - 如果是止损，trigger_price 应该低于当前价（卖出）或高于当前价（买入）
    // - tpsl 方向必须设置
}
```

**建议改进**:
添加触发单专门的验证逻辑，确保参数合理性。

---

## 报告 Bug

如果发现新的 Bug，请按以下格式记录：

### Bug 模板

```markdown
### Bug #X: [简短标题]

**状态**: Open | In Progress | Resolved
**严重性**: Critical | High | Medium | Low
**发现日期**: YYYY-MM-DD

**描述**:
[详细描述 Bug，包括预期行为和实际行为]

**复现步骤**:
1. 步骤 1
2. 步骤 2
3. ...

**复现代码**:
```zig
// 最小复现代码
```

**环境信息**:
- Zig 版本: 0.13.0
- 操作系统: Linux/macOS/Windows
- 相关配置: ...

**解决方案**:
[如果已知解决方案，描述修复方法]
```

---

## 待测试场景

以下场景需要在实际集成测试中验证：

- [ ] 高频订单创建（ID 唯一性）
- [ ] 并发订单更新（线程安全）
- [ ] 极端数值处理（Decimal 边界）
- [ ] 网络异常恢复（订单状态同步）
- [ ] 交易所 API 错误处理
- [ ] 长时间运行的内存稳定性

---

*请在发现问题时及时更新本文档*
