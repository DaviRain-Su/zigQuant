# 订单管理器 - Bug 追踪

> 已知问题和修复记录

**最后更新**: 2025-12-25

---

## 当前状态

订单管理器目前处于集成测试阶段，已修复 1 个关键内存管理 bug。本文档将持续更新，记录在开发、测试和生产环境中发现的问题。

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

### Bug #4: InvalidOrderResponse - Market IOC 订单响应解析失败

**状态**: Resolved ✅
**严重性**: High
**发现日期**: 2025-12-25
**修复日期**: 2025-12-25
**相关**: Position Management 集成测试

**描述**:
Market IOC 订单在立即成交后，响应格式为 `{"filled":{"totalSz":"0.001","avgPx":"88307.0","oid":45567444257}}`，但代码只处理了 `{"resting":...}` 格式，导致返回 `InvalidOrderResponse` 错误。

**实际情况**:
- 订单成功提交并成交（status=filled）
- 响应包含 filled 对象而非 resting 对象
- 代码解析失败返回 InvalidOrderResponse 错误

**预期行为**:
- 解析 filled 订单响应
- 提取 order ID、filled amount 和 avg price
- 返回 status=.filled 的 Order 对象

**解决方案**:
在 `connector.zig` 中修改响应解析逻辑，处理both "resting" 和 "filled" 状态：

```zig
const OrderResult = struct {
    order_id: u64,
    status: OrderStatus,
    filled_amount: Decimal,
    avg_fill_price: ?Decimal,
};

const order_result = blk: {
    const resp = response.response;
    if (resp.data) |data| {
        if (data.statuses.len > 0) {
            const status = data.statuses[0];

            // Check for resting (open) order
            if (status.resting) |resting| {
                break :blk OrderResult{
                    .order_id = resting.oid,
                    .status = OrderStatus.open,
                    .filled_amount = Decimal.ZERO,
                    .avg_fill_price = null,
                };
            }

            // Check for filled order (market IOC orders)
            if (status.filled) |filled| {
                const filled_amount = try hl_types.parseSize(filled.totalSz);
                const avg_price = try hl_types.parsePrice(filled.avgPx);
                break :blk OrderResult{
                    .order_id = filled.oid,
                    .status = OrderStatus.filled,
                    .filled_amount = filled_amount,
                    .avg_fill_price = avg_price,
                };
            }
        }
    }
    return error.InvalidOrderResponse;
};
```

**修改位置**:
- `src/exchange/hyperliquid/connector.zig`:430-470 - 响应解析逻辑

**测试验证**:
```bash
$ zig build test-position-management
```

输出：
```
Phase 4: Opening position (market buy)
✓ Market buy order submitted
  Order ID: 45567444257
  Status: filled
  Filled: 0.001 / 0.001

✅ ALL TESTS PASSED
✅ No memory leaks
```

**影响范围**:
- 所有 Market IOC 订单
- Position Management 集成测试
- OrderManager 订单状态跟踪

**关键学习点**:
1. **响应格式多样性**: Hyperliquid API 根据订单类型返回不同格式（resting vs filled）
2. **立即成交**: IOC 限价单若立即成交，返回 filled 状态而非 resting
3. **健壮性**: 需要处理所有可能的响应格式，避免假阴性错误

---

### Bug #5: client_order_id 内存管理问题 (use-after-free)

**状态**: Resolved ✅
**严重性**: High
**发现日期**: 2025-12-25
**修复日期**: 2025-12-25
**相关**: Hyperliquid 订单生命周期集成测试

**描述**:
在 `submitOrder()` 方法中，`client_order_id` 字符串在分配后立即被 `defer free` 释放，但同时该字符串被用作 `order_store` 的 HashMap key。当函数返回时，`client_order_id` 被释放，导致：
1. `Order.client_order_id` 指向已释放的内存（悬空指针）
2. HashMap 的 key 指向已释放的内存
3. 后续访问 `client_order_id` 可能读取垃圾数据或崩溃

**复现步骤**:
```zig
// order_manager.zig: submitOrder()
const client_order_id = try std.fmt.allocPrint(
    self.allocator,
    "order_{d}_{d}",
    .{ timestamp, self.next_order_id },
);
defer self.allocator.free(client_order_id);  // ❌ 过早释放

var order = Order{
    .client_order_id = client_order_id,  // 指针指向将被释放的内存
    // ...
};

try self.order_store.add(order);  // HashMap 使用 client_order_id 作为 key
// 函数返回时 defer 触发，client_order_id 被释放
// order.client_order_id 和 HashMap key 都变成悬空指针
```

**实际行为**:
- 订单创建后，`client_order_id` 可能显示为空或乱码
- HashMap 查询可能崩溃或返回错误结果
- 内存安全检查工具报告 use-after-free

**预期行为**:
- `client_order_id` 在订单整个生命周期内有效
- HashMap key 指向有效内存
- 内存泄漏检测显示 0 leaks

**解决方案**:

实施了两阶段内存管理策略：

1. **order_manager.zig**: 延后释放时机
```zig
const client_order_id = try std.fmt.allocPrint(...);
// 移除这里的 defer free

// 先让 order_store 复制 key
try self.order_store.add(order);

// 在 add() 完成后才释放原始字符串
defer self.allocator.free(client_order_id);
```

2. **order_store.zig**: 统一指针管理
```zig
pub fn add(self: *OrderStore, order: Order) !void {
    // 复制 client_order_id 作为 HashMap key
    const client_id_key = try self.allocator.dupe(u8, order.client_order_id);
    errdefer self.allocator.free(client_id_key);

    // 将订单存储到 HashMap
    const order_ptr = try self.allocator.create(Order);
    errdefer self.allocator.destroy(order_ptr);
    order_ptr.* = order;

    // 🔑 关键修复：统一指针
    // 让 Order.client_order_id 指向 HashMap key（唯一真相源）
    order_ptr.client_order_id = client_id_key;

    try self.order_map.put(client_id_key, order_ptr);
}
```

**修改位置**:
- `src/trading/order_manager.zig`:192-202 - 调整 `client_order_id` 释放时机
- `src/trading/order_store.zig`:41-49 - 统一 `client_order_id` 指针管理

**环境信息**:
- Zig 版本: 0.15.2
- 操作系统: Linux
- 测试: Hyperliquid testnet 集成测试

**测试验证**:
```bash
$ zig build test-order-lifecycle
```
输出：
```
Phase 4: Placing BTC order...
✓ Order submitted: client_order_id=order_1735140000_1

Phase 7: Verifying order is cancelled...
✓ Order status: cancelled (client_order_id 仍然有效)

✅ No memory leaks (0 bytes leaked)
```

**影响范围**:
- 所有使用 `client_order_id` 查询订单的操作
- `order_store` 的 HashMap 键值管理
- 订单生命周期管理

**关键学习点**:
1. **内存所有权**: HashMap key 的内存由 HashMap 拥有，不应在外部释放
2. **单一真相源**: `Order.client_order_id` 应指向 HashMap key，避免重复存储
3. **延迟释放**: 在确保所有引用完成后再释放临时字符串

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
