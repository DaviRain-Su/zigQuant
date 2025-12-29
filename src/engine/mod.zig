//! Engine Module
//!
//! Central management for all running trading components:
//! - Grid bots
//! - Strategy runners
//! - Backtest jobs
//!
//! This module provides lifecycle management, state persistence,
//! and API access to running components.

const std = @import("std");

pub const EngineManager = @import("manager.zig").EngineManager;
pub const GridRunner = @import("runners/grid_runner.zig").GridRunner;
pub const GridConfig = @import("runners/grid_runner.zig").GridConfig;
pub const GridStatus = @import("runners/grid_runner.zig").GridStatus;
pub const GridStats = @import("runners/grid_runner.zig").GridStats;
pub const GridOrder = @import("runners/grid_runner.zig").GridOrder;
pub const TradingMode = @import("runners/grid_runner.zig").TradingMode;

test {
    std.testing.refAllDecls(@This());
}
