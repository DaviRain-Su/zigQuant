//! RecoveryManager - Crash Recovery System (Story 045)
//!
//! Provides crash recovery capabilities:
//! - State checkpointing
//! - Fast recovery from checkpoints
//! - Exchange state synchronization
//!
//! Based on "Crash-only" design from NautilusTrader

const std = @import("std");
const Allocator = std.mem.Allocator;
const Decimal = @import("../core/decimal.zig").Decimal;
const Side = @import("../exchange/types.zig").Side;

/// Recovery Manager - Checkpoint and recovery system
pub const RecoveryManager = struct {
    allocator: Allocator,
    config: RecoveryConfig,

    // State storage
    checkpoints: std.ArrayListUnmanaged(SystemState),

    // Statistics
    checkpoint_count: u64,
    recovery_count: u64,
    last_checkpoint: i64,

    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: Allocator, config: RecoveryConfig) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .checkpoints = .{},
            .checkpoint_count = 0,
            .recovery_count = 0,
            .last_checkpoint = 0,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.checkpoints.items) |*cp| {
            self.freeState(cp);
        }
        self.checkpoints.deinit(self.allocator);
    }

    /// Create a checkpoint from current state
    pub fn checkpoint(self: *Self, state: SystemState) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();

        // Clone state with owned memory
        var saved_state = try self.cloneState(state);
        saved_state.timestamp = now;

        try self.checkpoints.append(self.allocator, saved_state);

        self.checkpoint_count += 1;
        self.last_checkpoint = now;

        // Cleanup old checkpoints
        try self.cleanupOldCheckpoints();
    }

    /// Recover from latest checkpoint
    pub fn recover(self: *Self) !RecoveryResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.checkpoints.items.len == 0) {
            return RecoveryResult{ .status = .no_checkpoint };
        }

        // Get latest checkpoint
        const latest = &self.checkpoints.items[self.checkpoints.items.len - 1];

        self.recovery_count += 1;

        return RecoveryResult{
            .status = .success,
            .checkpoint_time = latest.timestamp,
            .positions_restored = latest.positions.len,
            .orders_restored = latest.open_orders.len,
            .state = latest.*,
        };
    }

    /// Get checkpoint by index (0 = oldest)
    pub fn getCheckpoint(self: *Self, index: usize) ?SystemState {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (index >= self.checkpoints.items.len) return null;
        return self.checkpoints.items[index];
    }

    /// Get latest checkpoint
    pub fn getLatestCheckpoint(self: *Self) ?SystemState {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.checkpoints.items.len == 0) return null;
        return self.checkpoints.items[self.checkpoints.items.len - 1];
    }

    /// Get checkpoint count
    pub fn getCheckpointCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.checkpoints.items.len;
    }

    /// Clear all checkpoints
    pub fn clearCheckpoints(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.checkpoints.items) |*cp| {
            self.freeState(cp);
        }
        self.checkpoints.clearRetainingCapacity();
    }

    /// Get recovery statistics
    pub fn getStats(self: *Self) RecoveryStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return RecoveryStats{
            .checkpoint_count = self.checkpoint_count,
            .recovery_count = self.recovery_count,
            .last_checkpoint = self.last_checkpoint,
            .stored_checkpoints = self.checkpoints.items.len,
        };
    }

    // Internal helpers

    fn cleanupOldCheckpoints(self: *Self) !void {
        const now = std.time.timestamp();
        const max_age_secs = @as(i64, @intCast(self.config.max_checkpoint_age_hours)) * 3600;

        // Remove checkpoints exceeding max count or age
        while (self.checkpoints.items.len > self.config.max_checkpoints) {
            var cp = self.checkpoints.orderedRemove(0);
            self.freeState(&cp);
        }

        // Remove old checkpoints by age
        var i: usize = 0;
        while (i < self.checkpoints.items.len) {
            const cp = &self.checkpoints.items[i];
            if (now - cp.timestamp > max_age_secs) {
                var removed = self.checkpoints.orderedRemove(i);
                self.freeState(&removed);
            } else {
                i += 1;
            }
        }
    }

    fn cloneState(self: *Self, state: SystemState) !SystemState {
        // Clone positions
        var positions = try self.allocator.alloc(PositionState, state.positions.len);
        errdefer self.allocator.free(positions);

        for (state.positions, 0..) |pos, i| {
            positions[i] = .{
                .id = try self.allocator.dupe(u8, pos.id),
                .symbol = try self.allocator.dupe(u8, pos.symbol),
                .side = pos.side,
                .quantity = pos.quantity,
                .entry_price = pos.entry_price,
                .unrealized_pnl = pos.unrealized_pnl,
                .opened_at = pos.opened_at,
            };
        }

        // Clone orders
        var orders = try self.allocator.alloc(OrderState, state.open_orders.len);
        errdefer self.allocator.free(orders);

        for (state.open_orders, 0..) |order, i| {
            orders[i] = .{
                .id = try self.allocator.dupe(u8, order.id),
                .client_order_id = try self.allocator.dupe(u8, order.client_order_id),
                .symbol = try self.allocator.dupe(u8, order.symbol),
                .side = order.side,
                .order_type = order.order_type,
                .quantity = order.quantity,
                .filled_quantity = order.filled_quantity,
                .price = order.price,
                .status = order.status,
                .created_at = order.created_at,
            };
        }

        return SystemState{
            .timestamp = state.timestamp,
            .account = state.account,
            .positions = positions,
            .open_orders = orders,
        };
    }

    fn freeState(self: *Self, state: *SystemState) void {
        for (state.positions) |pos| {
            self.allocator.free(pos.id);
            self.allocator.free(pos.symbol);
        }
        self.allocator.free(state.positions);

        for (state.open_orders) |order| {
            self.allocator.free(order.id);
            self.allocator.free(order.client_order_id);
            self.allocator.free(order.symbol);
        }
        self.allocator.free(state.open_orders);
    }
};

/// Recovery Configuration
pub const RecoveryConfig = struct {
    // Checkpoint options
    checkpoint_on_trade: bool = true, // Save after each trade

    // Retention policy
    max_checkpoints: usize = 10, // Max checkpoints to keep
    max_checkpoint_age_hours: u32 = 24, // Max age in hours

    // Recovery options
    auto_recover: bool = true, // Auto-recover on start
    sync_with_exchange: bool = true, // Sync after recovery
    cancel_orphan_orders: bool = true, // Cancel orphan orders

    // Logging
    log_checkpoints: bool = true,
    log_recovery: bool = true,

    pub fn default() RecoveryConfig {
        return .{};
    }
};

/// System State (snapshot)
pub const SystemState = struct {
    timestamp: i64 = 0,
    account: AccountState = .{},
    positions: []PositionState = &[_]PositionState{},
    open_orders: []OrderState = &[_]OrderState{},
};

/// Account State
pub const AccountState = struct {
    equity: Decimal = Decimal.ZERO,
    balance: Decimal = Decimal.ZERO,
    available: Decimal = Decimal.ZERO,
    margin_used: Decimal = Decimal.ZERO,
    unrealized_pnl: Decimal = Decimal.ZERO,
};

/// Position State
pub const PositionState = struct {
    id: []const u8,
    symbol: []const u8,
    side: Side,
    quantity: Decimal,
    entry_price: Decimal,
    unrealized_pnl: Decimal,
    opened_at: i64,
};

/// Order State
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

/// Order Type (for recovery)
pub const OrderType = enum {
    market,
    limit,
    stop,
    stop_limit,
};

/// Order Status (for recovery)
pub const OrderStatus = enum {
    pending,
    open,
    partially_filled,
    filled,
    cancelled,
    rejected,
};

/// Recovery Result
pub const RecoveryResult = struct {
    status: RecoveryStatus,
    checkpoint_time: i64 = 0,
    positions_restored: usize = 0,
    orders_restored: usize = 0,
    state: ?SystemState = null,
    sync_result: ?SyncResult = null,
};

/// Recovery Status
pub const RecoveryStatus = enum {
    success,
    no_checkpoint,
    corrupted,
    sync_failed,
};

/// Sync Result
pub const SyncResult = struct {
    orphan_orders: usize = 0,
    stale_orders: usize = 0,
    orders_cancelled: usize = 0,
    position_mismatches: usize = 0,
    missing_positions: usize = 0,
    positions_updated: usize = 0,
    positions_added: usize = 0,
};

/// Recovery Statistics
pub const RecoveryStats = struct {
    checkpoint_count: u64,
    recovery_count: u64,
    last_checkpoint: i64,
    stored_checkpoints: usize,
};

// ============================================================================
// Tests
// ============================================================================

test "RecoveryManager: initialization" {
    const allocator = std.testing.allocator;

    var manager = RecoveryManager.init(allocator, RecoveryConfig.default());
    defer manager.deinit();

    const stats = manager.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.checkpoint_count);
    try std.testing.expectEqual(@as(usize, 0), stats.stored_checkpoints);
}

test "RecoveryManager: checkpoint and recover" {
    const allocator = std.testing.allocator;

    var manager = RecoveryManager.init(allocator, RecoveryConfig.default());
    defer manager.deinit();

    // Create a state to checkpoint
    var positions_data = [_]PositionState{
        .{
            .id = "pos-001",
            .symbol = "BTC-USDT",
            .side = .buy,
            .quantity = Decimal.fromFloat(1.0),
            .entry_price = Decimal.fromFloat(50000),
            .unrealized_pnl = Decimal.fromFloat(1000),
            .opened_at = 1000,
        },
    };

    var orders_data = [_]OrderState{
        .{
            .id = "order-001",
            .client_order_id = "client-001",
            .symbol = "BTC-USDT",
            .side = .buy,
            .order_type = .limit,
            .quantity = Decimal.fromFloat(0.5),
            .filled_quantity = Decimal.ZERO,
            .price = Decimal.fromFloat(49000),
            .status = .open,
            .created_at = 1000,
        },
    };

    const state = SystemState{
        .timestamp = std.time.timestamp(),
        .account = .{
            .equity = Decimal.fromFloat(100000),
            .balance = Decimal.fromFloat(95000),
            .available = Decimal.fromFloat(80000),
            .margin_used = Decimal.fromFloat(15000),
            .unrealized_pnl = Decimal.fromFloat(5000),
        },
        .positions = &positions_data,
        .open_orders = &orders_data,
    };

    // Create checkpoint
    try manager.checkpoint(state);

    // Verify checkpoint created
    try std.testing.expectEqual(@as(usize, 1), manager.getCheckpointCount());

    // Recover
    const result = try manager.recover();
    try std.testing.expectEqual(RecoveryStatus.success, result.status);
    try std.testing.expectEqual(@as(usize, 1), result.positions_restored);
    try std.testing.expectEqual(@as(usize, 1), result.orders_restored);
}

test "RecoveryManager: no checkpoint recovery" {
    const allocator = std.testing.allocator;

    var manager = RecoveryManager.init(allocator, RecoveryConfig.default());
    defer manager.deinit();

    const result = try manager.recover();
    try std.testing.expectEqual(RecoveryStatus.no_checkpoint, result.status);
}

test "RecoveryManager: multiple checkpoints" {
    const allocator = std.testing.allocator;

    var manager = RecoveryManager.init(allocator, RecoveryConfig.default());
    defer manager.deinit();

    // Create multiple checkpoints
    for (0..5) |i| {
        const state = SystemState{
            .timestamp = @intCast(i),
            .account = .{
                .equity = Decimal.fromFloat(100000 + @as(f64, @floatFromInt(i)) * 1000),
            },
            .positions = &[_]PositionState{},
            .open_orders = &[_]OrderState{},
        };
        try manager.checkpoint(state);
    }

    try std.testing.expectEqual(@as(usize, 5), manager.getCheckpointCount());

    // Recover returns latest
    const result = try manager.recover();
    try std.testing.expectEqual(RecoveryStatus.success, result.status);

    // Latest should have highest equity
    const latest = manager.getLatestCheckpoint();
    try std.testing.expect(latest != null);
}

test "RecoveryManager: max checkpoints limit" {
    const allocator = std.testing.allocator;

    const config = RecoveryConfig{
        .max_checkpoints = 3,
    };

    var manager = RecoveryManager.init(allocator, config);
    defer manager.deinit();

    // Create more checkpoints than max
    for (0..5) |i| {
        const state = SystemState{
            .timestamp = @intCast(i),
            .account = .{},
            .positions = &[_]PositionState{},
            .open_orders = &[_]OrderState{},
        };
        try manager.checkpoint(state);
    }

    // Should only keep max_checkpoints
    try std.testing.expectEqual(@as(usize, 3), manager.getCheckpointCount());
}

test "RecoveryManager: clear checkpoints" {
    const allocator = std.testing.allocator;

    var manager = RecoveryManager.init(allocator, RecoveryConfig.default());
    defer manager.deinit();

    // Add checkpoints
    for (0..3) |i| {
        const state = SystemState{
            .timestamp = @intCast(i),
            .account = .{},
            .positions = &[_]PositionState{},
            .open_orders = &[_]OrderState{},
        };
        try manager.checkpoint(state);
    }

    try std.testing.expectEqual(@as(usize, 3), manager.getCheckpointCount());

    // Clear
    manager.clearCheckpoints();
    try std.testing.expectEqual(@as(usize, 0), manager.getCheckpointCount());
}

test "RecoveryManager: stats" {
    const allocator = std.testing.allocator;

    var manager = RecoveryManager.init(allocator, RecoveryConfig.default());
    defer manager.deinit();

    // Create checkpoint
    const state = SystemState{
        .timestamp = 0,
        .account = .{},
        .positions = &[_]PositionState{},
        .open_orders = &[_]OrderState{},
    };
    try manager.checkpoint(state);

    // Recover
    _ = try manager.recover();

    const stats = manager.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.checkpoint_count);
    try std.testing.expectEqual(@as(u64, 1), stats.recovery_count);
    try std.testing.expect(stats.last_checkpoint > 0);
}
