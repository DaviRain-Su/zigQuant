# CrashRecovery - 实现细节

> 深入了解崩溃恢复的内部实现

**最后更新**: 2025-12-27

---

## 数据结构

```zig
pub const RecoveryManager = struct {
    allocator: Allocator,
    config: RecoveryConfig,
    state_store: StateStore,
    execution: *ExecutionEngine,
    positions: *PositionTracker,
    account: *Account,

    last_checkpoint: i64 = 0,
    checkpoint_count: u64 = 0,
    recovery_count: u64 = 0,
    mutex: std.Thread.Mutex,
};

pub const RecoveryConfig = struct {
    checkpoint_dir: []const u8 = "./checkpoints",
    checkpoint_interval_ms: u64 = 60000,
    checkpoint_on_trade: bool = true,
    max_checkpoints: usize = 10,
    max_checkpoint_age_hours: u32 = 24,
    auto_recover: bool = true,
    sync_with_exchange: bool = true,
    cancel_orphan_orders: bool = true,
};

pub const SystemState = struct {
    timestamp: i64,
    account: AccountState,
    positions: []PositionState,
    open_orders: []OrderState,
    strategy_states: ?[]StrategyState = null,
};
```

---

## 核心算法

### 创建检查点

```zig
pub fn checkpoint(self: *Self) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const now = std.time.timestamp();

    // 收集状态
    const state = SystemState{
        .timestamp = now,
        .account = self.collectAccountState(),
        .positions = try self.collectPositions(),
        .open_orders = try self.collectOpenOrders(),
    };

    // 保存
    const path = try self.state_store.save(state);
    defer self.allocator.free(path);

    self.last_checkpoint = now;
    self.checkpoint_count += 1;

    // 清理旧检查点
    try self.state_store.cleanup(
        self.config.max_checkpoints,
        self.config.max_checkpoint_age_hours,
    );
}
```

### 序列化

```zig
fn serialize(self: *Self, state: SystemState) ![]u8 {
    var buffer = std.ArrayList(u8).init(self.allocator);
    const writer = buffer.writer();

    // 版本
    try writer.writeInt(u32, 1, .little);

    // 时间戳
    try writer.writeInt(i64, state.timestamp, .little);

    // 账户
    try self.serializeAccount(writer, state.account);

    // 仓位
    try writer.writeInt(u32, @intCast(state.positions.len), .little);
    for (state.positions) |pos| {
        try self.serializePosition(writer, pos);
    }

    // 订单
    try writer.writeInt(u32, @intCast(state.open_orders.len), .little);
    for (state.open_orders) |order| {
        try self.serializeOrder(writer, order);
    }

    return buffer.toOwnedSlice();
}
```

### 恢复

```zig
pub fn recover(self: *Self) !RecoveryResult {
    self.mutex.lock();
    defer self.mutex.unlock();

    // 加载最新检查点
    const state = try self.state_store.loadLatest() orelse {
        return RecoveryResult{ .status = .no_checkpoint };
    };

    // 恢复账户
    try self.restoreAccount(state.account);

    // 恢复仓位
    try self.restorePositions(state.positions);

    // 恢复订单
    try self.restoreOrders(state.open_orders);

    // 同步
    var sync_result: ?SyncResult = null;
    if (self.config.sync_with_exchange) {
        sync_result = try self.syncWithExchange();
    }

    self.recovery_count += 1;

    return RecoveryResult{
        .status = .success,
        .checkpoint_time = state.timestamp,
        .positions_restored = state.positions.len,
        .orders_restored = state.open_orders.len,
        .sync_result = sync_result,
    };
}
```

### 交易所同步

```zig
pub fn syncWithExchange(self: *Self) !SyncResult {
    var result = SyncResult{};

    // 获取交易所状态
    const exchange_orders = try self.execution.fetchOpenOrdersFromExchange();
    const exchange_positions = try self.execution.fetchPositionsFromExchange();

    const local_orders = try self.execution.getOpenOrders();

    // 找出孤立订单
    for (exchange_orders) |ex_order| {
        var found = false;
        for (local_orders) |local_order| {
            if (std.mem.eql(u8, ex_order.id, local_order.id)) {
                found = true;
                break;
            }
        }

        if (!found) {
            result.orphan_orders += 1;
            if (self.config.cancel_orphan_orders) {
                try self.execution.cancelOrder(ex_order.id);
                result.orders_cancelled += 1;
            }
        }
    }

    // 对比仓位
    for (exchange_positions) |ex_pos| {
        // 更新本地仓位以匹配交易所
        // ...
    }

    return result;
}
```

---

## 文件格式

```
+-------------------+
| Magic (4 bytes)   | "ZQCK"
+-------------------+
| Version (4 bytes) | 1
+-------------------+
| Timestamp (8 bytes)|
+-------------------+
| Account Data      |
+-------------------+
| Position Count (4)|
+-------------------+
| Positions Data    |
+-------------------+
| Order Count (4)   |
+-------------------+
| Orders Data       |
+-------------------+
| CRC32 (4 bytes)   |
+-------------------+
```

---

*完整实现请参考: `src/recovery/recovery_manager.zig`*
