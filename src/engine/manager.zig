//! Engine Manager
//!
//! Central manager for all running trading components.
//! Provides lifecycle management, state persistence, and API access.
//!
//! Architecture:
//! - All strategies (including Grid) run through StrategyRunner
//! - Backtests run through BacktestRunner
//! - Unified API for all strategy types

const std = @import("std");
const Allocator = std.mem.Allocator;

const backtest_runner = @import("runners/backtest_runner.zig");
const BacktestRunner = backtest_runner.BacktestRunner;
const BacktestRequest = backtest_runner.BacktestRequest;
const BacktestStatus = backtest_runner.BacktestStatus;
const BacktestProgress = backtest_runner.BacktestProgress;
const BacktestResultSummary = backtest_runner.BacktestResultSummary;

const strategy_runner = @import("runners/strategy_runner.zig");
const StrategyRunner = strategy_runner.StrategyRunner;
const StrategyRequest = strategy_runner.StrategyRequest;
const StrategyStatus = strategy_runner.StrategyStatus;
const StrategyStats = strategy_runner.StrategyStats;
const SignalHistoryEntry = strategy_runner.SignalHistoryEntry;

/// Engine Manager - manages all running components
pub const EngineManager = struct {
    allocator: Allocator,

    // Backtest runners by ID
    backtest_runners: std.StringHashMap(*BacktestRunner),

    // Strategy runners by ID (includes all strategy types: dual_ma, rsi, grid, etc.)
    strategy_runners: std.StringHashMap(*StrategyRunner),

    // Statistics
    total_backtests_started: u64,
    total_backtests_completed: u64,
    total_strategies_started: u64,
    total_strategies_stopped: u64,

    // System state
    kill_switch_active: bool,
    kill_switch_reason: ?[]const u8,

    // Thread safety
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// Initialize the engine manager
    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .backtest_runners = std.StringHashMap(*BacktestRunner).init(allocator),
            .strategy_runners = std.StringHashMap(*StrategyRunner).init(allocator),
            .total_backtests_started = 0,
            .total_backtests_completed = 0,
            .total_strategies_started = 0,
            .total_strategies_stopped = 0,
            .kill_switch_active = false,
            .kill_switch_reason = null,
            .mutex = .{},
        };
    }

    /// Clean up all resources
    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Stop and clean up all backtest runners
        var bt_it = self.backtest_runners.valueIterator();
        while (bt_it.next()) |runner| {
            runner.*.deinit();
        }
        self.backtest_runners.deinit();

        // Stop and clean up all strategy runners
        var strat_it = self.strategy_runners.valueIterator();
        while (strat_it.next()) |runner| {
            runner.*.deinit();
        }
        self.strategy_runners.deinit();

        // Clean up kill switch reason
        if (self.kill_switch_reason) |reason| {
            self.allocator.free(reason);
        }
    }

    // ========================================================================
    // Backtest API
    // ========================================================================

    /// Start a new backtest job
    pub fn startBacktest(self: *Self, id: []const u8, request: BacktestRequest) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if already exists
        if (self.backtest_runners.contains(id)) {
            return error.BacktestAlreadyExists;
        }

        // Create and start the runner
        const runner = try BacktestRunner.init(self.allocator, id, request);
        errdefer runner.deinit();

        try runner.start();

        // Store in map
        try self.backtest_runners.put(runner.id, runner);
        self.total_backtests_started += 1;
    }

    /// Cancel a running backtest
    pub fn cancelBacktest(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.backtest_runners.get(id) orelse return error.BacktestNotFound;
        try runner.cancel();
    }

    /// Get backtest status
    pub fn getBacktestStatus(self: *Self, id: []const u8) !BacktestStatus {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.backtest_runners.get(id) orelse return error.BacktestNotFound;
        return runner.getStatus();
    }

    /// Get backtest progress
    pub fn getBacktestProgress(self: *Self, id: []const u8) !BacktestProgress {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.backtest_runners.get(id) orelse return error.BacktestNotFound;
        return runner.getProgress();
    }

    /// Get backtest result summary
    pub fn getBacktestResult(self: *Self, id: []const u8) !?BacktestResultSummary {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.backtest_runners.get(id) orelse return error.BacktestNotFound;
        return runner.getResultSummary();
    }

    /// Remove a completed backtest
    pub fn removeBacktest(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = self.backtest_runners.fetchRemove(id) orelse return error.BacktestNotFound;
        const runner = entry.value;

        if (runner.status == .completed or runner.status == .failed or runner.status == .cancelled) {
            self.total_backtests_completed += 1;
        }

        runner.deinit();
    }

    /// Get count of running backtests
    pub fn getRunningBacktestCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.getRunningBacktestCountUnlocked();
    }

    /// List all backtests
    pub fn listBacktests(self: *Self, allocator: Allocator) ![]BacktestSummary {
        self.mutex.lock();
        defer self.mutex.unlock();

        var list = std.ArrayList(BacktestSummary){};
        errdefer list.deinit(allocator);

        var it = self.backtest_runners.iterator();
        while (it.next()) |entry| {
            const runner = entry.value_ptr.*;
            const progress = runner.getProgress();

            try list.append(allocator, .{
                .id = entry.key_ptr.*,
                .strategy = runner.request.strategy,
                .symbol = runner.request.symbol,
                .status = runner.status.toString(),
                .progress = progress.progress,
                .trades_so_far = progress.trades_so_far,
                .elapsed_seconds = progress.elapsed_seconds,
            });
        }

        return list.toOwnedSlice(allocator);
    }

    // ========================================================================
    // Strategy API (Unified - supports all strategy types including Grid)
    // ========================================================================

    /// Start a new strategy (supports all types: dual_ma, rsi, grid, etc.)
    pub fn startStrategy(self: *Self, id: []const u8, request: StrategyRequest) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check kill switch
        if (self.kill_switch_active) {
            return error.KillSwitchActive;
        }

        // Check if already exists
        if (self.strategy_runners.contains(id)) {
            return error.StrategyAlreadyExists;
        }

        // Validate grid parameters if this is a grid strategy
        if (request.isGridStrategy()) {
            try request.validateGridParams();
        }

        // Create and start the strategy runner
        const runner = try StrategyRunner.init(self.allocator, id, request);
        errdefer runner.deinit();

        try runner.start();

        // Store in strategy runners map
        try self.strategy_runners.put(runner.id, runner);
        self.total_strategies_started += 1;
    }

    /// Stop a strategy
    pub fn stopStrategy(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = self.strategy_runners.fetchRemove(id) orelse return error.StrategyNotFound;
        const runner = entry.value;

        runner.stop() catch {};
        runner.deinit();
        self.total_strategies_stopped += 1;
    }

    /// Pause a strategy
    pub fn pauseStrategy(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.strategy_runners.get(id) orelse return error.StrategyNotFound;
        try runner.pause();
    }

    /// Resume a paused strategy
    pub fn resumeStrategy(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.strategy_runners.get(id) orelse return error.StrategyNotFound;
        try runner.unpause();
    }

    /// Get strategy status
    pub fn getStrategyStatus(self: *Self, id: []const u8) !StrategyStatus {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.strategy_runners.get(id) orelse return error.StrategyNotFound;
        return runner.getStatus();
    }

    /// Get strategy statistics
    pub fn getStrategyStats(self: *Self, id: []const u8) !StrategyStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.strategy_runners.get(id) orelse return error.StrategyNotFound;
        return runner.getStats();
    }

    /// Get strategy signal history
    pub fn getStrategySignalHistory(self: *Self, allocator: Allocator, id: []const u8, limit: usize) ![]SignalHistoryEntry {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.strategy_runners.get(id) orelse return error.StrategyNotFound;
        return runner.getSignalHistory(allocator, limit);
    }

    /// Update strategy parameters
    pub fn updateStrategyParams(self: *Self, id: []const u8, params_json: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.strategy_runners.get(id) orelse return error.StrategyNotFound;
        try runner.updateParams(params_json);
    }

    /// Get strategy parameters
    pub fn getStrategyParams(self: *Self, id: []const u8) !?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.strategy_runners.get(id) orelse return error.StrategyNotFound;
        return runner.getParams();
    }

    /// Get count of running strategies
    pub fn getRunningStrategyCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.getRunningStrategyCountUnlocked();
    }

    fn getRunningStrategyCountUnlocked(self: *Self) usize {
        var count: usize = 0;

        var strat_it = self.strategy_runners.valueIterator();
        while (strat_it.next()) |runner| {
            if (runner.*.status == .running or runner.*.status == .paused) count += 1;
        }

        return count;
    }

    /// List all strategies
    pub fn listStrategies(self: *Self, allocator: Allocator) ![]StrategySummary {
        self.mutex.lock();
        defer self.mutex.unlock();

        var list = std.ArrayList(StrategySummary){};
        errdefer list.deinit(allocator);

        var strat_it = self.strategy_runners.iterator();
        while (strat_it.next()) |entry| {
            const runner = entry.value_ptr.*;
            const stats = runner.getStats();

            try list.append(allocator, .{
                .id = entry.key_ptr.*,
                .strategy = runner.request.strategy,
                .symbol = runner.request.symbol,
                .status = runner.status.toString(),
                .mode = runner.request.mode.toString(),
                .realized_pnl = stats.realized_pnl,
                .current_position = stats.current_position,
                .total_signals = stats.total_signals,
                .total_trades = stats.total_trades,
                .win_rate = stats.win_rate,
                .uptime_seconds = stats.uptime_seconds,
            });
        }

        return list.toOwnedSlice(allocator);
    }

    // ========================================================================
    // System API (Kill Switch)
    // ========================================================================

    /// Activate kill switch - stops all trading
    pub fn activateKillSwitch(self: *Self, reason: []const u8, cancel_orders: bool, close_positions: bool) !KillSwitchResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        _ = cancel_orders;
        _ = close_positions;

        var result = KillSwitchResult{};

        // Stop all strategies (including grid strategies)
        var strat_it = self.strategy_runners.valueIterator();
        while (strat_it.next()) |runner| {
            if (runner.*.status == .running or runner.*.status == .paused) {
                runner.*.stop() catch {};
                result.strategies_stopped += 1;
            }
        }

        // Store reason
        if (self.kill_switch_reason) |old| {
            self.allocator.free(old);
        }
        self.kill_switch_reason = try self.allocator.dupe(u8, reason);
        self.kill_switch_active = true;

        return result;
    }

    /// Deactivate kill switch
    pub fn deactivateKillSwitch(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.kill_switch_active = false;
        if (self.kill_switch_reason) |reason| {
            self.allocator.free(reason);
            self.kill_switch_reason = null;
        }
    }

    /// Check if kill switch is active
    pub fn isKillSwitchActive(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.kill_switch_active;
    }

    /// Get system health status
    pub fn getSystemHealth(self: *Self) SystemHealth {
        self.mutex.lock();
        defer self.mutex.unlock();

        return .{
            .status = if (self.kill_switch_active) "kill_switch" else "healthy",
            .running_backtests = self.getRunningBacktestCountUnlocked(),
            .running_strategies = self.getRunningStrategyCountUnlocked(),
            .kill_switch_active = self.kill_switch_active,
            .kill_switch_reason = self.kill_switch_reason,
        };
    }

    fn getRunningBacktestCountUnlocked(self: *Self) usize {
        var count: usize = 0;
        var it = self.backtest_runners.valueIterator();
        while (it.next()) |runner| {
            if (runner.*.status == .running or runner.*.status == .queued) count += 1;
        }
        return count;
    }

    /// Get manager statistics
    pub fn getManagerStats(self: *Self) ManagerStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var running: usize = 0;
        var stopped: usize = 0;
        var total_pnl: f64 = 0;
        var total_trades: u32 = 0;

        var it = self.strategy_runners.valueIterator();
        while (it.next()) |runner| {
            const stats = runner.*.getStats();
            total_pnl += stats.realized_pnl;
            total_trades += stats.total_trades;

            if (runner.*.status == .running or runner.*.status == .paused) {
                running += 1;
            } else {
                stopped += 1;
            }
        }

        return .{
            .total_strategies = self.strategy_runners.count(),
            .running_strategies = running,
            .stopped_strategies = stopped,
            .total_strategies_started = self.total_strategies_started,
            .total_strategies_stopped = self.total_strategies_stopped,
            .total_realized_pnl = total_pnl,
            .total_trades = total_trades,
        };
    }
};

/// Summary of a single backtest
pub const BacktestSummary = struct {
    id: []const u8,
    strategy: []const u8,
    symbol: []const u8,
    status: []const u8,
    progress: f64,
    trades_so_far: u32,
    elapsed_seconds: i64,
};

/// Summary of a single strategy
pub const StrategySummary = struct {
    id: []const u8,
    strategy: []const u8,
    symbol: []const u8,
    status: []const u8,
    mode: []const u8,
    realized_pnl: f64,
    current_position: f64,
    total_signals: u32,
    total_trades: u32,
    win_rate: f64,
    uptime_seconds: i64,
};

/// Manager statistics
pub const ManagerStats = struct {
    total_strategies: usize,
    running_strategies: usize,
    stopped_strategies: usize,
    total_strategies_started: u64,
    total_strategies_stopped: u64,
    total_realized_pnl: f64,
    total_trades: u32,
};

/// Kill switch result
pub const KillSwitchResult = struct {
    strategies_stopped: usize = 0,
    orders_cancelled: usize = 0,
    positions_closed: usize = 0,
};

/// System health status
pub const SystemHealth = struct {
    status: []const u8,
    running_backtests: usize,
    running_strategies: usize,
    kill_switch_active: bool,
    kill_switch_reason: ?[]const u8,
};

// ============================================================================
// Tests
// ============================================================================

test "EngineManager init and deinit" {
    const allocator = std.testing.allocator;
    var manager = EngineManager.init(allocator);
    defer manager.deinit();

    try std.testing.expectEqual(@as(usize, 0), manager.strategy_runners.count());
}

test "EngineManager strategy lifecycle" {
    const allocator = std.testing.allocator;
    var manager = EngineManager.init(allocator);
    defer manager.deinit();

    const request = StrategyRequest{
        .strategy = "dual_ma",
        .symbol = "BTC-USDT",
        .timeframe = "1h",
        .mode = .paper,
    };

    // Start strategy
    try manager.startStrategy("test_strategy", request);
    try std.testing.expectEqual(@as(usize, 1), manager.strategy_runners.count());

    // Get status
    const status = try manager.getStrategyStatus("test_strategy");
    try std.testing.expectEqual(StrategyStatus.running, status);

    // Stop strategy
    try manager.stopStrategy("test_strategy");
    try std.testing.expectEqual(@as(usize, 0), manager.strategy_runners.count());
}

test "EngineManager grid strategy via unified API" {
    const allocator = std.testing.allocator;
    var manager = EngineManager.init(allocator);
    defer manager.deinit();

    const request = StrategyRequest{
        .strategy = "grid",
        .symbol = "BTC-USDT",
        .timeframe = "1h",
        .mode = .paper,
        .upper_price = 100000,
        .lower_price = 90000,
        .grid_count = 10,
        .order_size = 0.001,
    };

    // Validate that it's recognized as grid
    try std.testing.expect(request.isGridStrategy());

    // Start grid strategy
    try manager.startStrategy("test_grid", request);
    try std.testing.expectEqual(@as(usize, 1), manager.strategy_runners.count());

    // Stop grid strategy
    try manager.stopStrategy("test_grid");
    try std.testing.expectEqual(@as(usize, 0), manager.strategy_runners.count());
}

test "EngineManager kill switch" {
    const allocator = std.testing.allocator;
    var manager = EngineManager.init(allocator);
    defer manager.deinit();

    try std.testing.expect(!manager.isKillSwitchActive());

    const result = try manager.activateKillSwitch("test reason", false, false);
    _ = result;

    try std.testing.expect(manager.isKillSwitchActive());

    manager.deactivateKillSwitch();
    try std.testing.expect(!manager.isKillSwitchActive());
}
