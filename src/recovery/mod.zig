//! Recovery Module (v0.8.0)
//!
//! Provides crash recovery capabilities:
//! - RecoveryManager: Checkpoint and recovery system
//! - SystemState: Serializable state snapshot
//! - SyncResult: Exchange synchronization result

const std = @import("std");

// Core recovery modules
pub const recovery_manager = @import("recovery_manager.zig");

// Re-export main types
pub const RecoveryManager = recovery_manager.RecoveryManager;
pub const RecoveryConfig = recovery_manager.RecoveryConfig;
pub const RecoveryResult = recovery_manager.RecoveryResult;
pub const RecoveryStatus = recovery_manager.RecoveryStatus;
pub const RecoveryStats = recovery_manager.RecoveryStats;

pub const SystemState = recovery_manager.SystemState;
pub const AccountState = recovery_manager.AccountState;
pub const PositionState = recovery_manager.PositionState;
pub const OrderState = recovery_manager.OrderState;
pub const OrderType = recovery_manager.OrderType;
pub const OrderStatus = recovery_manager.OrderStatus;

pub const SyncResult = recovery_manager.SyncResult;

test {
    std.testing.refAllDecls(@This());
    _ = recovery_manager;
}
