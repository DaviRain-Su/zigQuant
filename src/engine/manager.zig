//! Engine Manager
//!
//! Central manager for all running trading components.
//! Provides lifecycle management, state persistence, and API access.

const std = @import("std");
const Allocator = std.mem.Allocator;

const grid_runner = @import("runners/grid_runner.zig");
const GridRunner = grid_runner.GridRunner;
const GridConfig = grid_runner.GridConfig;
const GridStatus = grid_runner.GridStatus;
const GridStats = grid_runner.GridStats;
const GridOrder = grid_runner.GridOrder;

const backtest_runner = @import("runners/backtest_runner.zig");
const BacktestRunner = backtest_runner.BacktestRunner;
const BacktestRequest = backtest_runner.BacktestRequest;
const BacktestStatus = backtest_runner.BacktestStatus;
const BacktestProgress = backtest_runner.BacktestProgress;
const BacktestResultSummary = backtest_runner.BacktestResultSummary;

/// Engine Manager - manages all running components
pub const EngineManager = struct {
    allocator: Allocator,

    // Grid runners by ID
    grid_runners: std.StringHashMap(*GridRunner),

    // Backtest runners by ID
    backtest_runners: std.StringHashMap(*BacktestRunner),

    // Statistics
    total_grids_started: u64,
    total_grids_stopped: u64,
    total_backtests_started: u64,
    total_backtests_completed: u64,

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
            .grid_runners = std.StringHashMap(*GridRunner).init(allocator),
            .backtest_runners = std.StringHashMap(*BacktestRunner).init(allocator),
            .total_grids_started = 0,
            .total_grids_stopped = 0,
            .total_backtests_started = 0,
            .total_backtests_completed = 0,
            .kill_switch_active = false,
            .kill_switch_reason = null,
            .mutex = .{},
        };
    }

    /// Clean up all resources
    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Stop and clean up all grid runners
        var grid_it = self.grid_runners.valueIterator();
        while (grid_it.next()) |runner| {
            runner.*.deinit();
        }
        self.grid_runners.deinit();

        // Stop and clean up all backtest runners
        var bt_it = self.backtest_runners.valueIterator();
        while (bt_it.next()) |runner| {
            runner.*.deinit();
        }
        self.backtest_runners.deinit();

        // Clean up kill switch reason
        if (self.kill_switch_reason) |reason| {
            self.allocator.free(reason);
        }
    }

    // ========================================================================
    // Grid Trading API
    // ========================================================================

    /// Start a new grid trading bot
    pub fn startGrid(self: *Self, id: []const u8, config: GridConfig) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if already exists
        if (self.grid_runners.contains(id)) {
            return error.GridAlreadyExists;
        }

        // Create and start the runner
        const runner = try GridRunner.init(self.allocator, id, config);
        errdefer runner.deinit();

        try runner.start();

        // Store in map (need to copy the ID since runner owns it)
        try self.grid_runners.put(runner.id, runner);
        self.total_grids_started += 1;
    }

    /// Stop a grid trading bot
    pub fn stopGrid(self: *Self, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = self.grid_runners.fetchRemove(id) orelse return error.GridNotFound;
        const runner = entry.value;

        runner.stop() catch {};
        runner.deinit();
        self.total_grids_stopped += 1;
    }

    /// Get grid status
    pub fn getGridStatus(self: *Self, id: []const u8) !GridStatus {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.grid_runners.get(id) orelse return error.GridNotFound;
        return runner.getStatus();
    }

    /// Get grid statistics
    pub fn getGridStats(self: *Self, id: []const u8) !GridStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.grid_runners.get(id) orelse return error.GridNotFound;
        return runner.getStats();
    }

    /// Get grid orders
    pub fn getGridOrders(self: *Self, allocator: Allocator, id: []const u8) ![]GridOrder {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.grid_runners.get(id) orelse return error.GridNotFound;
        return runner.getOrders(allocator);
    }

    /// Update grid configuration
    pub fn updateGrid(self: *Self, id: []const u8, config: GridConfig) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const runner = self.grid_runners.get(id) orelse return error.GridNotFound;
        try runner.updateConfig(config);
    }

    /// List all grid IDs
    pub fn listGrids(self: *Self, allocator: Allocator) ![]const []const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var list = std.ArrayList([]const u8){};
        errdefer list.deinit(allocator);

        var it = self.grid_runners.keyIterator();
        while (it.next()) |key| {
            try list.append(allocator, key.*);
        }

        return list.toOwnedSlice(allocator);
    }

    /// Get count of running grids
    pub fn getRunningGridCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        var count: usize = 0;
        var it = self.grid_runners.valueIterator();
        while (it.next()) |runner| {
            if (runner.*.status == .running) count += 1;
        }
        return count;
    }

    /// Get all grids summary
    pub fn getAllGridsSummary(self: *Self, allocator: Allocator) ![]GridSummary {
        self.mutex.lock();
        defer self.mutex.unlock();

        var list = std.ArrayList(GridSummary){};
        errdefer list.deinit(allocator);

        var it = self.grid_runners.iterator();
        while (it.next()) |entry| {
            const runner = entry.value_ptr.*;
            const stats = runner.getStats();

            try list.append(allocator, .{
                .id = entry.key_ptr.*,
                .pair = .{
                    .base = runner.config.pair.base,
                    .quote = runner.config.pair.quote,
                },
                .status = runner.status.toString(),
                .mode = @tagName(runner.config.mode),
                .realized_pnl = stats.realized_pnl,
                .current_position = stats.current_position,
                .total_trades = stats.total_trades,
                .uptime_seconds = stats.uptime_seconds,
            });
        }

        return list.toOwnedSlice(allocator);
    }

    /// Get manager statistics
    pub fn getManagerStats(self: *Self) ManagerStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var running: usize = 0;
        var stopped: usize = 0;
        var total_pnl: f64 = 0;
        var total_trades: u32 = 0;

        var it = self.grid_runners.valueIterator();
        while (it.next()) |runner| {
            const stats = runner.*.getStats();
            total_pnl += stats.realized_pnl;
            total_trades += stats.total_trades;

            if (runner.*.status == .running) {
                running += 1;
            } else {
                stopped += 1;
            }
        }

        return .{
            .total_grids = self.grid_runners.count(),
            .running_grids = running,
            .stopped_grids = stopped,
            .total_grids_started = self.total_grids_started,
            .total_grids_stopped = self.total_grids_stopped,
            .total_realized_pnl = total_pnl,
            .total_trades = total_trades,
        };
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

        var count: usize = 0;
        var it = self.backtest_runners.valueIterator();
        while (it.next()) |runner| {
            if (runner.*.status == .running or runner.*.status == .queued) count += 1;
        }
        return count;
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
    // System API (Kill Switch)
    // ========================================================================

    /// Activate kill switch - stops all trading
    pub fn activateKillSwitch(self: *Self, reason: []const u8, cancel_orders: bool, close_positions: bool) !KillSwitchResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        _ = cancel_orders;
        _ = close_positions;

        var result = KillSwitchResult{};

        // Stop all grids
        var grid_it = self.grid_runners.valueIterator();
        while (grid_it.next()) |runner| {
            if (runner.*.status == .running) {
                runner.*.stop() catch {};
                result.grids_stopped += 1;
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
            .running_grids = self.getRunningGridCountUnlocked(),
            .running_backtests = self.getRunningBacktestCountUnlocked(),
            .kill_switch_active = self.kill_switch_active,
            .kill_switch_reason = self.kill_switch_reason,
        };
    }

    fn getRunningGridCountUnlocked(self: *Self) usize {
        var count: usize = 0;
        var it = self.grid_runners.valueIterator();
        while (it.next()) |runner| {
            if (runner.*.status == .running) count += 1;
        }
        return count;
    }

    fn getRunningBacktestCountUnlocked(self: *Self) usize {
        var count: usize = 0;
        var it = self.backtest_runners.valueIterator();
        while (it.next()) |runner| {
            if (runner.*.status == .running or runner.*.status == .queued) count += 1;
        }
        return count;
    }
};

/// Summary of a single grid
pub const GridSummary = struct {
    id: []const u8,
    pair: struct { base: []const u8, quote: []const u8 },
    status: []const u8,
    mode: []const u8,
    realized_pnl: f64,
    current_position: f64,
    total_trades: u32,
    uptime_seconds: i64,
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

/// Manager statistics
pub const ManagerStats = struct {
    total_grids: usize,
    running_grids: usize,
    stopped_grids: usize,
    total_grids_started: u64,
    total_grids_stopped: u64,
    total_realized_pnl: f64,
    total_trades: u32,
};

/// Kill switch result
pub const KillSwitchResult = struct {
    grids_stopped: usize = 0,
    strategies_stopped: usize = 0,
    orders_cancelled: usize = 0,
    positions_closed: usize = 0,
};

/// System health status
pub const SystemHealth = struct {
    status: []const u8,
    running_grids: usize,
    running_backtests: usize,
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

    try std.testing.expectEqual(@as(usize, 0), manager.grid_runners.count());
}

test "EngineManager grid lifecycle" {
    const allocator = std.testing.allocator;
    var manager = EngineManager.init(allocator);
    defer manager.deinit();

    const root = @import("../root.zig");
    const Decimal = root.Decimal;

    const config = GridConfig{
        .pair = .{ .base = "BTC", .quote = "USDC" },
        .upper_price = Decimal.fromFloat(100000),
        .lower_price = Decimal.fromFloat(90000),
        .grid_count = 5,
        .order_size = Decimal.fromFloat(0.001),
        .mode = .paper,
    };

    // Start grid
    try manager.startGrid("test_grid", config);
    try std.testing.expectEqual(@as(usize, 1), manager.grid_runners.count());

    // Get status
    const status = try manager.getGridStatus("test_grid");
    try std.testing.expectEqual(GridStatus.running, status);

    // Stop grid
    try manager.stopGrid("test_grid");
    try std.testing.expectEqual(@as(usize, 0), manager.grid_runners.count());
}
