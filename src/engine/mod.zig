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
pub const ManagerStats = @import("manager.zig").ManagerStats;
pub const GridSummary = @import("manager.zig").GridSummary;
pub const BacktestSummary = @import("manager.zig").BacktestSummary;
pub const KillSwitchResult = @import("manager.zig").KillSwitchResult;
pub const SystemHealth = @import("manager.zig").SystemHealth;

// Grid Runner exports
pub const GridRunner = @import("runners/grid_runner.zig").GridRunner;
pub const GridConfig = @import("runners/grid_runner.zig").GridConfig;
pub const GridStatus = @import("runners/grid_runner.zig").GridStatus;
pub const GridStats = @import("runners/grid_runner.zig").GridStats;
pub const GridOrder = @import("runners/grid_runner.zig").GridOrder;
pub const TradingMode = @import("runners/grid_runner.zig").TradingMode;

// Backtest Runner exports
pub const BacktestRunner = @import("runners/backtest_runner.zig").BacktestRunner;
pub const BacktestRequest = @import("runners/backtest_runner.zig").BacktestRequest;
pub const BacktestStatus = @import("runners/backtest_runner.zig").BacktestStatus;
pub const BacktestProgress = @import("runners/backtest_runner.zig").BacktestProgress;
pub const BacktestResultSummary = @import("runners/backtest_runner.zig").BacktestResultSummary;

test {
    std.testing.refAllDecls(@This());
}
