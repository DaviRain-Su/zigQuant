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

/// Engine Manager - manages all running components
pub const EngineManager = struct {
    allocator: Allocator,

    // Grid runners by ID
    grid_runners: std.StringHashMap(*GridRunner),

    // Statistics
    total_grids_started: u64,
    total_grids_stopped: u64,

    // Thread safety
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// Initialize the engine manager
    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .grid_runners = std.StringHashMap(*GridRunner).init(allocator),
            .total_grids_started = 0,
            .total_grids_stopped = 0,
            .mutex = .{},
        };
    }

    /// Clean up all resources
    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Stop and clean up all grid runners
        var it = self.grid_runners.valueIterator();
        while (it.next()) |runner| {
            runner.*.deinit();
        }
        self.grid_runners.deinit();
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
