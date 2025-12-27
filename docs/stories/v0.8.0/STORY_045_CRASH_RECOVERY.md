# Story 045: Crash Recovery

**版本**: v0.8.0
**状态**: 📋 规划中
**优先级**: P1 (重要)
**预计时间**: 3-4 天
**依赖**: Story 044 (告警和通知系统)
**参考**: NautilusTrader Crash-only Recovery

---

## 目标

实现崩溃恢复机制，确保系统在意外崩溃后能够快速恢复状态，避免订单丢失和仓位不一致。

## 背景

在生产交易系统中，崩溃是不可避免的。一个好的恢复机制需要:
1. **状态持久化**: 定期保存关键状态
2. **快速恢复**: 从检查点快速重建状态
3. **数据一致性**: 确保恢复后的状态正确
4. **交易所同步**: 与交易所状态对账

借鉴 NautilusTrader 的 "Crash-only" 设计理念：系统总是假设可能崩溃，通过持久化保证恢复能力。

---

## 核心功能

### 1. 恢复管理器

```zig
/// 恢复管理器
pub const RecoveryManager = struct {
    allocator: Allocator,
    config: RecoveryConfig,
    state_store: StateStore,
    execution: *ExecutionEngine,
    positions: *PositionTracker,
    account: *Account,

    // 检查点状态
    last_checkpoint: i64 = 0,
    checkpoint_count: u64 = 0,
    recovery_count: u64 = 0,

    // 锁
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        config: RecoveryConfig,
        execution: *ExecutionEngine,
        positions: *PositionTracker,
        account: *Account,
    ) !Self {
        const state_store = try StateStore.init(allocator, config.checkpoint_dir);

        return .{
            .allocator = allocator,
            .config = config,
            .state_store = state_store,
            .execution = execution,
            .positions = positions,
            .account = account,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.state_store.deinit();
    }
};
```

### 2. 恢复配置

```zig
/// 恢复配置
pub const RecoveryConfig = struct {
    // 检查点目录
    checkpoint_dir: []const u8 = "./checkpoints",

    // 检查点间隔
    checkpoint_interval_ms: u64 = 60000,  // 1分钟
    checkpoint_on_trade: bool = true,      // 每次交易后保存

    // 保留策略
    max_checkpoints: usize = 10,           // 最多保留检查点数
    max_checkpoint_age_hours: u32 = 24,    // 检查点最大保留时间

    // 恢复选项
    auto_recover: bool = true,             // 启动时自动恢复
    sync_with_exchange: bool = true,       // 恢复后与交易所同步
    cancel_orphan_orders: bool = true,     // 取消孤立订单

    // 日志
    log_checkpoints: bool = true,
    log_recovery: bool = true,
};
```

### 3. 状态存储

```zig
/// 状态存储
pub const StateStore = struct {
    allocator: Allocator,
    base_dir: []const u8,

    const Self = @This();

    pub fn init(allocator: Allocator, base_dir: []const u8) !Self {
        // 确保目录存在
        std.fs.cwd().makePath(base_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        return .{
            .allocator = allocator,
            .base_dir = base_dir,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// 保存状态
    pub fn save(self: *Self, state: SystemState) ![]const u8 {
        const filename = try std.fmt.allocPrint(
            self.allocator,
            "{s}/checkpoint_{d}.bin",
            .{ self.base_dir, state.timestamp },
        );
        defer self.allocator.free(filename);

        // 序列化状态
        const data = try self.serialize(state);
        defer self.allocator.free(data);

        // 写入文件
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        try file.writeAll(data);

        // 写入校验和
        const checksum = self.calculateChecksum(data);
        try file.writeAll(&checksum);

        return try self.allocator.dupe(u8, filename);
    }

    /// 加载最新状态
    pub fn loadLatest(self: *Self) !?SystemState {
        const checkpoints = try self.listCheckpoints();
        defer self.allocator.free(checkpoints);

        if (checkpoints.len == 0) return null;

        // 按时间戳排序，取最新
        std.mem.sort(CheckpointInfo, checkpoints, {}, compareByTimestamp);
        const latest = checkpoints[checkpoints.len - 1];

        return self.load(latest.path);
    }

    /// 加载指定检查点
    pub fn load(self: *Self, path: []const u8) !SystemState {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        // 读取数据
        const stat = try file.stat();
        const data = try self.allocator.alloc(u8, stat.size - 4);
        defer self.allocator.free(data);

        _ = try file.readAll(data);

        // 验证校验和
        var checksum: [4]u8 = undefined;
        _ = try file.readAll(&checksum);

        const expected = self.calculateChecksum(data);
        if (!std.mem.eql(u8, &checksum, &expected)) {
            return error.ChecksumMismatch;
        }

        // 反序列化
        return self.deserialize(data);
    }

    /// 列出所有检查点
    pub fn listCheckpoints(self: *Self) ![]CheckpointInfo {
        var list = std.ArrayList(CheckpointInfo).init(self.allocator);

        var dir = try std.fs.cwd().openIterableDir(self.base_dir, .{});
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (std.mem.startsWith(u8, entry.name, "checkpoint_") and
                std.mem.endsWith(u8, entry.name, ".bin"))
            {
                const timestamp = std.fmt.parseInt(
                    i64,
                    entry.name["checkpoint_".len .. entry.name.len - 4],
                    10,
                ) catch continue;

                try list.append(.{
                    .path = try std.fs.path.join(self.allocator, &.{ self.base_dir, entry.name }),
                    .timestamp = timestamp,
                    .size = entry.size,
                });
            }
        }

        return list.toOwnedSlice();
    }

    /// 清理旧检查点
    pub fn cleanup(self: *Self, max_count: usize, max_age_hours: u32) !void {
        var checkpoints = try self.listCheckpoints();
        defer {
            for (checkpoints) |cp| self.allocator.free(cp.path);
            self.allocator.free(checkpoints);
        }

        if (checkpoints.len <= max_count) return;

        std.mem.sort(CheckpointInfo, checkpoints, {}, compareByTimestamp);

        const now = std.time.timestamp();
        const max_age_secs = @as(i64, max_age_hours) * 3600;

        // 删除超出数量或过期的检查点
        for (checkpoints[0 .. checkpoints.len - max_count]) |cp| {
            if (now - cp.timestamp > max_age_secs) {
                std.fs.cwd().deleteFile(cp.path) catch {};
            }
        }
    }

    fn serialize(self: *Self, state: SystemState) ![]u8 {
        _ = self;
        // 使用简单的二进制序列化
        // 实际实现可以使用 MessagePack, Protobuf 等
        var buffer = std.ArrayList(u8).init(self.allocator);
        const writer = buffer.writer();

        // 写入版本
        try writer.writeInt(u32, 1, .little);

        // 写入时间戳
        try writer.writeInt(i64, state.timestamp, .little);

        // 写入账户状态
        try self.serializeAccount(writer, state.account);

        // 写入仓位
        try writer.writeInt(u32, @intCast(state.positions.len), .little);
        for (state.positions) |pos| {
            try self.serializePosition(writer, pos);
        }

        // 写入未完成订单
        try writer.writeInt(u32, @intCast(state.open_orders.len), .little);
        for (state.open_orders) |order| {
            try self.serializeOrder(writer, order);
        }

        return buffer.toOwnedSlice();
    }

    fn deserialize(self: *Self, data: []const u8) !SystemState {
        var stream = std.io.fixedBufferStream(data);
        const reader = stream.reader();

        // 读取版本
        const version = try reader.readInt(u32, .little);
        if (version != 1) return error.UnsupportedVersion;

        // 读取时间戳
        const timestamp = try reader.readInt(i64, .little);

        // 读取账户状态
        const account = try self.deserializeAccount(reader);

        // 读取仓位
        const position_count = try reader.readInt(u32, .little);
        var positions = try self.allocator.alloc(PositionState, position_count);
        for (positions) |*pos| {
            pos.* = try self.deserializePosition(reader);
        }

        // 读取未完成订单
        const order_count = try reader.readInt(u32, .little);
        var orders = try self.allocator.alloc(OrderState, order_count);
        for (orders) |*order| {
            order.* = try self.deserializeOrder(reader);
        }

        return SystemState{
            .timestamp = timestamp,
            .account = account,
            .positions = positions,
            .open_orders = orders,
        };
    }

    fn calculateChecksum(self: *Self, data: []const u8) [4]u8 {
        _ = self;
        // 使用 CRC32
        const crc = std.hash.Crc32.hash(data);
        return @bitCast(crc);
    }
};

pub const CheckpointInfo = struct {
    path: []const u8,
    timestamp: i64,
    size: u64,
};

fn compareByTimestamp(context: void, a: CheckpointInfo, b: CheckpointInfo) bool {
    _ = context;
    return a.timestamp < b.timestamp;
}
```

### 4. 系统状态

```zig
/// 系统状态
pub const SystemState = struct {
    timestamp: i64,
    account: AccountState,
    positions: []PositionState,
    open_orders: []OrderState,
    strategy_states: ?[]StrategyState = null,
};

pub const AccountState = struct {
    equity: Decimal,
    balance: Decimal,
    available: Decimal,
    margin_used: Decimal,
    unrealized_pnl: Decimal,
};

pub const PositionState = struct {
    id: []const u8,
    symbol: []const u8,
    side: Side,
    quantity: Decimal,
    entry_price: Decimal,
    unrealized_pnl: Decimal,
    opened_at: i64,
};

pub const OrderState = struct {
    id: []const u8,
    client_order_id: []const u8,
    symbol: []const u8,
    side: Side,
    order_type: OrderType,
    quantity: Decimal,
    filled_quantity: Decimal,
    price: ?Decimal,
    status: OrderStatus,
    created_at: i64,
};

pub const StrategyState = struct {
    name: []const u8,
    state_data: []const u8,  // 策略自定义状态
};
```

### 5. 创建检查点

```zig
/// 创建检查点
pub fn checkpoint(self: *Self) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const now = std.time.timestamp();

    // 收集当前状态
    const state = SystemState{
        .timestamp = now,
        .account = self.collectAccountState(),
        .positions = try self.collectPositions(),
        .open_orders = try self.collectOpenOrders(),
    };

    // 保存到存储
    const path = try self.state_store.save(state);
    defer self.allocator.free(path);

    self.last_checkpoint = now;
    self.checkpoint_count += 1;

    if (self.config.log_checkpoints) {
        std.log.info("[RECOVERY] Checkpoint created: {s}", .{path});
    }

    // 清理旧检查点
    try self.state_store.cleanup(
        self.config.max_checkpoints,
        self.config.max_checkpoint_age_hours,
    );
}

/// 交易后检查点 (如果配置启用)
pub fn checkpointOnTrade(self: *Self) !void {
    if (!self.config.checkpoint_on_trade) return;
    try self.checkpoint();
}

/// 定期检查点任务
pub fn startPeriodicCheckpoint(self: *Self) void {
    const thread = std.Thread.spawn(.{}, struct {
        fn run(manager: *Self) void {
            while (true) {
                std.time.sleep(manager.config.checkpoint_interval_ms * std.time.ns_per_ms);
                manager.checkpoint() catch |err| {
                    std.log.err("[RECOVERY] Checkpoint failed: {}", .{err});
                };
            }
        }
    }.run, .{self}) catch return;
    thread.detach();
}

fn collectAccountState(self: *Self) AccountState {
    return .{
        .equity = self.account.equity,
        .balance = self.account.balance,
        .available = self.account.available_balance,
        .margin_used = self.account.margin_used,
        .unrealized_pnl = self.account.unrealized_pnl,
    };
}

fn collectPositions(self: *Self) ![]PositionState {
    const all = self.positions.getAll();
    var result = try self.allocator.alloc(PositionState, all.len);

    for (all, 0..) |pos, i| {
        result[i] = .{
            .id = pos.id,
            .symbol = pos.symbol,
            .side = pos.side,
            .quantity = pos.quantity,
            .entry_price = pos.entry_price,
            .unrealized_pnl = pos.unrealized_pnl,
            .opened_at = pos.opened_at,
        };
    }

    return result;
}

fn collectOpenOrders(self: *Self) ![]OrderState {
    const open = try self.execution.getOpenOrders();
    var result = try self.allocator.alloc(OrderState, open.len);

    for (open, 0..) |order, i| {
        result[i] = .{
            .id = order.id,
            .client_order_id = order.client_order_id,
            .symbol = order.symbol,
            .side = order.side,
            .order_type = order.order_type,
            .quantity = order.quantity,
            .filled_quantity = order.filled_quantity,
            .price = order.price,
            .status = order.status,
            .created_at = order.created_at,
        };
    }

    return result;
}
```

### 6. 恢复流程

```zig
/// 从检查点恢复
pub fn recover(self: *Self) !RecoveryResult {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.config.log_recovery) {
        std.log.info("[RECOVERY] Starting recovery...", .{});
    }

    // 1. 加载最新检查点
    const state = try self.state_store.loadLatest() orelse {
        std.log.info("[RECOVERY] No checkpoint found, starting fresh", .{});
        return RecoveryResult{ .status = .no_checkpoint };
    };

    if (self.config.log_recovery) {
        std.log.info("[RECOVERY] Loaded checkpoint from {d}", .{state.timestamp});
    }

    // 2. 恢复账户状态
    try self.restoreAccount(state.account);

    // 3. 恢复仓位
    try self.restorePositions(state.positions);

    // 4. 恢复订单状态
    try self.restoreOrders(state.open_orders);

    // 5. 与交易所同步 (如果配置启用)
    var sync_result: ?SyncResult = null;
    if (self.config.sync_with_exchange) {
        sync_result = try self.syncWithExchange();
    }

    self.recovery_count += 1;

    if (self.config.log_recovery) {
        std.log.info("[RECOVERY] Recovery completed", .{});
    }

    return RecoveryResult{
        .status = .success,
        .checkpoint_time = state.timestamp,
        .positions_restored = state.positions.len,
        .orders_restored = state.open_orders.len,
        .sync_result = sync_result,
    };
}

fn restoreAccount(self: *Self, state: AccountState) !void {
    self.account.equity = state.equity;
    self.account.balance = state.balance;
    self.account.available_balance = state.available;
    self.account.margin_used = state.margin_used;
    self.account.unrealized_pnl = state.unrealized_pnl;
}

fn restorePositions(self: *Self, states: []PositionState) !void {
    for (states) |state| {
        try self.positions.restore(Position{
            .id = state.id,
            .symbol = state.symbol,
            .side = state.side,
            .quantity = state.quantity,
            .entry_price = state.entry_price,
            .unrealized_pnl = state.unrealized_pnl,
            .opened_at = state.opened_at,
        });
    }
}

fn restoreOrders(self: *Self, states: []OrderState) !void {
    for (states) |state| {
        try self.execution.restoreOrder(Order{
            .id = state.id,
            .client_order_id = state.client_order_id,
            .symbol = state.symbol,
            .side = state.side,
            .order_type = state.order_type,
            .quantity = state.quantity,
            .filled_quantity = state.filled_quantity,
            .price = state.price,
            .status = state.status,
            .created_at = state.created_at,
        });
    }
}

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
```

### 7. 交易所同步

```zig
/// 与交易所状态同步
pub fn syncWithExchange(self: *Self) !SyncResult {
    std.log.info("[RECOVERY] Syncing with exchange...", .{});

    var result = SyncResult{};

    // 1. 获取交易所当前订单
    const exchange_orders = try self.execution.fetchOpenOrdersFromExchange();
    defer self.allocator.free(exchange_orders);

    // 2. 获取交易所当前仓位
    const exchange_positions = try self.execution.fetchPositionsFromExchange();
    defer self.allocator.free(exchange_positions);

    // 3. 对比订单
    const local_orders = try self.execution.getOpenOrders();

    // 找出孤立订单 (在交易所但不在本地)
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
                std.log.warn("[RECOVERY] Cancelled orphan order: {s}", .{ex_order.id});
            }
        }
    }

    // 找出已失效订单 (在本地但不在交易所)
    for (local_orders) |local_order| {
        var found = false;
        for (exchange_orders) |ex_order| {
            if (std.mem.eql(u8, local_order.id, ex_order.id)) {
                found = true;
                break;
            }
        }

        if (!found) {
            result.stale_orders += 1;
            try self.execution.markOrderCompleted(local_order.id);
            std.log.info("[RECOVERY] Marked stale order as completed: {s}", .{local_order.id});
        }
    }

    // 4. 对比仓位
    const local_positions = self.positions.getAll();

    for (exchange_positions) |ex_pos| {
        var found = false;
        for (local_positions) |local_pos| {
            if (std.mem.eql(u8, ex_pos.symbol, local_pos.symbol)) {
                found = true;

                // 检查数量差异
                if (ex_pos.quantity.cmp(local_pos.quantity) != .eq) {
                    result.position_mismatches += 1;
                    std.log.warn("[RECOVERY] Position mismatch for {s}: local={d}, exchange={d}", .{
                        ex_pos.symbol,
                        local_pos.quantity.toFloat(),
                        ex_pos.quantity.toFloat(),
                    });

                    // 更新为交易所状态
                    try self.positions.update(ex_pos.symbol, ex_pos.quantity);
                    result.positions_updated += 1;
                }
                break;
            }
        }

        if (!found) {
            // 交易所有仓位但本地没有
            result.missing_positions += 1;
            try self.positions.add(ex_pos);
            result.positions_added += 1;
            std.log.info("[RECOVERY] Added missing position: {s}", .{ex_pos.symbol});
        }
    }

    std.log.info("[RECOVERY] Sync completed: {} orders cancelled, {} positions updated", .{
        result.orders_cancelled,
        result.positions_updated,
    });

    return result;
}

pub const SyncResult = struct {
    orphan_orders: usize = 0,
    stale_orders: usize = 0,
    orders_cancelled: usize = 0,
    position_mismatches: usize = 0,
    missing_positions: usize = 0,
    positions_updated: usize = 0,
    positions_added: usize = 0,
};
```

### 8. 自动恢复

```zig
/// 启动时自动恢复 (如果配置启用)
pub fn autoRecover(self: *Self) !?RecoveryResult {
    if (!self.config.auto_recover) return null;

    // 检查是否有检查点
    const checkpoints = try self.state_store.listCheckpoints();
    defer {
        for (checkpoints) |cp| self.allocator.free(cp.path);
        self.allocator.free(checkpoints);
    }

    if (checkpoints.len == 0) {
        std.log.info("[RECOVERY] No checkpoints found, skipping auto-recovery", .{});
        return null;
    }

    // 执行恢复
    return try self.recover();
}

/// 获取恢复统计
pub fn getStats(self: *Self) RecoveryStats {
    return RecoveryStats{
        .checkpoint_count = self.checkpoint_count,
        .recovery_count = self.recovery_count,
        .last_checkpoint = self.last_checkpoint,
    };
}

pub const RecoveryStats = struct {
    checkpoint_count: u64,
    recovery_count: u64,
    last_checkpoint: i64,
};
```

---

## 实现任务

### Task 1: 实现 StateStore
- [ ] 文件系统操作
- [ ] 序列化/反序列化
- [ ] 校验和验证
- [ ] 检查点管理

### Task 2: 实现 checkpoint
- [ ] 状态收集
- [ ] 保存逻辑
- [ ] 定期检查点

### Task 3: 实现 recover
- [ ] 加载检查点
- [ ] 恢复账户
- [ ] 恢复仓位
- [ ] 恢复订单

### Task 4: 实现交易所同步
- [ ] 获取交易所状态
- [ ] 对比本地状态
- [ ] 处理差异

### Task 5: 实现自动恢复
- [ ] 启动时检测
- [ ] 自动恢复流程

### Task 6: 单元测试
- [ ] 序列化测试
- [ ] 检查点测试
- [ ] 恢复测试
- [ ] 同步测试

---

## 验收标准

### 功能
- [ ] 检查点正确保存和加载
- [ ] 恢复后状态一致
- [ ] 与交易所同步正确
- [ ] 孤立订单正确处理

### 性能
- [ ] 检查点创建 < 1s
- [ ] 恢复时间 < 10s
- [ ] 不影响正常交易

### 测试
- [ ] 模拟崩溃恢复
- [ ] 数据完整性测试
- [ ] 边界条件测试

---

## 示例代码

```zig
const std = @import("std");
const RecoveryManager = @import("recovery").RecoveryManager;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 配置
    const config = RecoveryConfig{
        .checkpoint_dir = "./checkpoints",
        .checkpoint_interval_ms = 60000,
        .auto_recover = true,
        .sync_with_exchange = true,
    };

    // 创建恢复管理器
    var recovery = try RecoveryManager.init(
        allocator,
        config,
        &execution,
        &positions,
        &account,
    );
    defer recovery.deinit();

    // 自动恢复 (如果有检查点)
    if (try recovery.autoRecover()) |result| {
        std.debug.print("Recovered from checkpoint at {d}\n", .{result.checkpoint_time});
        std.debug.print("Positions: {}, Orders: {}\n", .{
            result.positions_restored,
            result.orders_restored,
        });

        if (result.sync_result) |sync| {
            std.debug.print("Sync: {} orders cancelled, {} positions updated\n", .{
                sync.orders_cancelled,
                sync.positions_updated,
            });
        }
    }

    // 启动定期检查点
    recovery.startPeriodicCheckpoint();

    // 交易逻辑...

    // 交易后创建检查点
    try recovery.checkpointOnTrade();
}
```

---

## 相关文档

- [v0.8.0 Overview](./OVERVIEW.md)
- [Story 044: 告警和通知系统](./STORY_044_ALERT_SYSTEM.md)
- [竞争分析 - NautilusTrader](../../architecture/COMPETITIVE_ANALYSIS.md)

---

**Story ID**: STORY-045
**状态**: 📋 规划中
**创建时间**: 2025-12-27
