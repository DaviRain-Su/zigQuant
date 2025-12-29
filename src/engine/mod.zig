//! Engine Module
//!
//! Central management for all running trading components:
//! - Strategy runners (all strategy types including Grid)
//! - Backtest jobs
//!
//! This module provides lifecycle management, state persistence,
//! and API access to running components.
//!
//! Architecture Note:
//! All strategies (including grid trading) run through StrategyRunner.
//! Grid strategies are created with strategy="grid" and use GridStrategy
//! from the strategy/builtin module.

const std = @import("std");

// Engine Manager exports
pub const EngineManager = @import("manager.zig").EngineManager;
pub const ManagerStats = @import("manager.zig").ManagerStats;
pub const BacktestSummary = @import("manager.zig").BacktestSummary;
pub const StrategySummary = @import("manager.zig").StrategySummary;
pub const KillSwitchResult = @import("manager.zig").KillSwitchResult;
pub const SystemHealth = @import("manager.zig").SystemHealth;

// Backtest Runner exports
pub const BacktestRunner = @import("runners/backtest_runner.zig").BacktestRunner;
pub const BacktestRequest = @import("runners/backtest_runner.zig").BacktestRequest;
pub const BacktestStatus = @import("runners/backtest_runner.zig").BacktestStatus;
pub const BacktestProgress = @import("runners/backtest_runner.zig").BacktestProgress;
pub const BacktestResultSummary = @import("runners/backtest_runner.zig").BacktestResultSummary;

// Strategy Runner exports (unified - supports all strategy types including grid)
pub const StrategyRunner = @import("runners/strategy_runner.zig").StrategyRunner;
pub const StrategyRequest = @import("runners/strategy_runner.zig").StrategyRequest;
pub const StrategyStatus = @import("runners/strategy_runner.zig").StrategyStatus;
pub const StrategyStats = @import("runners/strategy_runner.zig").StrategyStats;
pub const SignalHistoryEntry = @import("runners/strategy_runner.zig").SignalHistoryEntry;
pub const StrategyTradingMode = @import("runners/strategy_runner.zig").TradingMode;

// Re-export TradingMode as a convenience alias
pub const TradingMode = StrategyTradingMode;

test {
    std.testing.refAllDecls(@This());
}
