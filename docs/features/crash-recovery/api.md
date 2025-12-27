# CrashRecovery - API 参考

> 完整的 API 文档

**最后更新**: 2025-12-27

---

## 类型定义

```zig
pub const RecoveryConfig = struct {
    checkpoint_dir: []const u8 = "./checkpoints",
    checkpoint_interval_ms: u64 = 60000,
    checkpoint_on_trade: bool = true,
    max_checkpoints: usize = 10,
    auto_recover: bool = true,
    sync_with_exchange: bool = true,
    cancel_orphan_orders: bool = true,
};

pub const RecoveryResult = struct {
    status: RecoveryStatus,
    checkpoint_time: i64 = 0,
    positions_restored: usize = 0,
    orders_restored: usize = 0,
    sync_result: ?SyncResult = null,
};

pub const RecoveryStatus = enum {
    success,
    no_checkpoint,
    corrupted,
    sync_failed,
};

pub const SyncResult = struct {
    orphan_orders: usize = 0,
    stale_orders: usize = 0,
    orders_cancelled: usize = 0,
    position_mismatches: usize = 0,
    positions_updated: usize = 0,
};
```

---

## 函数

### `checkpoint`
创建检查点，保存当前状态

### `checkpointOnTrade`
交易后创建检查点 (如果配置启用)

### `recover`
从最新检查点恢复

### `autoRecover`
启动时自动恢复 (如果有检查点)

### `syncWithExchange`
与交易所状态同步

### `startPeriodicCheckpoint`
启动定期检查点任务

### `getStats`
获取恢复统计信息

---

## 完整示例

```zig
const recovery = @import("zigQuant").recovery;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var rm = try recovery.RecoveryManager.init(allocator, .{
        .checkpoint_dir = "./checkpoints",
        .auto_recover = true,
    }, &execution, &positions, &account);
    defer rm.deinit();

    // 自动恢复
    if (try rm.autoRecover()) |result| {
        std.debug.print("Recovered: {} positions, {} orders\n", .{
            result.positions_restored,
            result.orders_restored,
        });
    }

    // 启动定期检查点
    rm.startPeriodicCheckpoint();

    // 主循环...
}
```
