/// Result Loader for Backtest Results
///
/// Loads previously saved backtest results from JSON files.
/// Supports:
/// - Loading single results
/// - Comparing multiple results
/// - Extracting specific metrics

const std = @import("std");
const root = @import("../root.zig");

const BacktestResult = root.BacktestResult;
const BacktestConfig = root.BacktestConfig;
const Trade = root.Trade;
const EquitySnapshot = root.EquitySnapshot;
const Decimal = root.Decimal;
const Timestamp = root.Timestamp;
const TradingPair = root.TradingPair;
const Timeframe = root.Timeframe;
const PositionSide = root.PositionSide;

// ============================================================================
// Result Loader
// ============================================================================

/// Loads backtest results from JSON files
pub const ResultLoader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ResultLoader {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ResultLoader) void {
        _ = self;
    }

    /// Load backtest result from JSON file
    pub fn loadFromFile(self: *ResultLoader, file_path: []const u8) !LoadedResult {
        // Read file contents
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        if (file_size > 100 * 1024 * 1024) {
            return error.FileTooLarge;
        }

        const contents = try self.allocator.alloc(u8, @intCast(file_size));
        defer self.allocator.free(contents);

        const bytes_read = try file.readAll(contents);
        if (bytes_read != file_size) {
            return error.IncompleteRead;
        }

        return try self.loadFromString(contents);
    }

    /// Load backtest result from JSON string
    pub fn loadFromString(self: *ResultLoader, json_str: []const u8) !LoadedResult {
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            json_str,
            .{},
        ) catch return error.InvalidJSON;
        defer parsed.deinit();

        return try self.parseResult(parsed.value);
    }

    fn parseResult(self: *ResultLoader, value: std.json.Value) !LoadedResult {
        if (value != .object) return error.InvalidJSONStructure;

        const root_obj = value.object;

        // Parse metadata
        const metadata = try self.parseMetadata(root_obj.get("metadata") orelse return error.MissingMetadata);

        // Parse config
        const config = try self.parseConfig(root_obj.get("config") orelse return error.MissingConfig);

        // Parse metrics
        const metrics = try self.parseMetrics(root_obj.get("metrics") orelse return error.MissingMetrics);

        // Parse trades (optional)
        var trades: std.ArrayListUnmanaged(LoadedTrade) = .{};
        if (root_obj.get("trades")) |trades_val| {
            if (trades_val == .array) {
                for (trades_val.array.items) |trade_val| {
                    const trade = try self.parseTrade(trade_val);
                    try trades.append(self.allocator, trade);
                }
            }
        }

        // Parse equity curve (optional)
        var equity: std.ArrayListUnmanaged(LoadedEquityPoint) = .{};
        if (root_obj.get("equity_curve")) |equity_val| {
            if (equity_val == .array) {
                for (equity_val.array.items) |point_val| {
                    const point = try self.parseEquityPoint(point_val);
                    try equity.append(self.allocator, point);
                }
            }
        }

        return LoadedResult{
            .allocator = self.allocator,
            .metadata = metadata,
            .config = config,
            .metrics = metrics,
            .trades = try trades.toOwnedSlice(self.allocator),
            .equity_curve = try equity.toOwnedSlice(self.allocator),
        };
    }

    fn parseMetadata(self: *ResultLoader, value: std.json.Value) !LoadedMetadata {
        if (value != .object) return error.InvalidMetadata;
        const obj = value.object;

        // Dupe strings to own the memory
        const strategy = if (getString(obj, "strategy")) |s| try self.allocator.dupe(u8, s) else try self.allocator.dupe(u8, "unknown");
        const pair = if (getString(obj, "pair")) |s| try self.allocator.dupe(u8, s) else try self.allocator.dupe(u8, "unknown");
        const timeframe = if (getString(obj, "timeframe")) |s| try self.allocator.dupe(u8, s) else try self.allocator.dupe(u8, "1h");

        return LoadedMetadata{
            .strategy = strategy,
            .pair = pair,
            .timeframe = timeframe,
            .start_time = getInteger(obj, "start_time") orelse 0,
            .end_time = getInteger(obj, "end_time") orelse 0,
            .total_candles = @intCast(getInteger(obj, "total_candles") orelse 0),
        };
    }

    fn parseConfig(self: *ResultLoader, value: std.json.Value) !LoadedConfig {
        _ = self;
        if (value != .object) return error.InvalidConfig;
        const obj = value.object;

        return LoadedConfig{
            .initial_capital = getFloat(obj, "initial_capital") orelse 10000.0,
            .commission_rate = getFloat(obj, "commission_rate") orelse 0.001,
            .slippage = getFloat(obj, "slippage") orelse 0.0005,
        };
    }

    fn parseMetrics(self: *ResultLoader, value: std.json.Value) !LoadedMetrics {
        _ = self;
        if (value != .object) return error.InvalidMetrics;
        const obj = value.object;

        return LoadedMetrics{
            .total_trades = @intCast(getInteger(obj, "total_trades") orelse 0),
            .winning_trades = @intCast(getInteger(obj, "winning_trades") orelse 0),
            .losing_trades = @intCast(getInteger(obj, "losing_trades") orelse 0),
            .win_rate = getFloat(obj, "win_rate") orelse 0.0,
            .net_profit = getFloat(obj, "net_profit") orelse 0.0,
            .profit_factor = getFloat(obj, "profit_factor") orelse 0.0,
            .max_drawdown = getFloat(obj, "max_drawdown") orelse 0.0,
            .final_equity = getFloat(obj, "final_equity") orelse 0.0,
            .total_return = getFloat(obj, "total_return") orelse 0.0,
        };
    }

    fn parseTrade(self: *ResultLoader, value: std.json.Value) !LoadedTrade {
        if (value != .object) return error.InvalidTrade;
        const obj = value.object;

        // Dupe the side string
        const side = if (getString(obj, "side")) |s| try self.allocator.dupe(u8, s) else try self.allocator.dupe(u8, "long");

        return LoadedTrade{
            .id = @intCast(getInteger(obj, "id") orelse 0),
            .entry_time = getInteger(obj, "entry_time") orelse 0,
            .exit_time = getInteger(obj, "exit_time") orelse 0,
            .entry_price = getFloat(obj, "entry_price") orelse 0.0,
            .exit_price = getFloat(obj, "exit_price") orelse 0.0,
            .size = getFloat(obj, "size") orelse 0.0,
            .side = side,
            .pnl = getFloat(obj, "pnl") orelse 0.0,
            .pnl_percent = getFloat(obj, "pnl_percent") orelse 0.0,
            .commission = getFloat(obj, "commission") orelse 0.0,
        };
    }

    fn parseEquityPoint(self: *ResultLoader, value: std.json.Value) !LoadedEquityPoint {
        _ = self;
        if (value != .object) return error.InvalidEquityPoint;
        const obj = value.object;

        return LoadedEquityPoint{
            .time = getInteger(obj, "time") orelse 0,
            .equity = getFloat(obj, "equity") orelse 0.0,
        };
    }
};

// Helper functions for JSON parsing
fn getString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const val = obj.get(key) orelse return null;
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}

fn getInteger(obj: std.json.ObjectMap, key: []const u8) ?i64 {
    const val = obj.get(key) orelse return null;
    return switch (val) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => null,
    };
}

fn getFloat(obj: std.json.ObjectMap, key: []const u8) ?f64 {
    const val = obj.get(key) orelse return null;
    return switch (val) {
        .float => |f| f,
        .integer => |i| @floatFromInt(i),
        else => null,
    };
}

// ============================================================================
// Loaded Data Types
// ============================================================================

/// Loaded result from JSON
pub const LoadedResult = struct {
    allocator: std.mem.Allocator,
    metadata: LoadedMetadata,
    config: LoadedConfig,
    metrics: LoadedMetrics,
    trades: []LoadedTrade,
    equity_curve: []LoadedEquityPoint,

    pub fn deinit(self: *LoadedResult) void {
        // Free metadata strings
        self.allocator.free(self.metadata.strategy);
        self.allocator.free(self.metadata.pair);
        self.allocator.free(self.metadata.timeframe);

        // Free trade side strings
        for (self.trades) |trade| {
            self.allocator.free(trade.side);
        }

        self.allocator.free(self.trades);
        self.allocator.free(self.equity_curve);
    }
};

pub const LoadedMetadata = struct {
    strategy: []const u8,
    pair: []const u8,
    timeframe: []const u8,
    start_time: i64,
    end_time: i64,
    total_candles: usize,
};

pub const LoadedConfig = struct {
    initial_capital: f64,
    commission_rate: f64,
    slippage: f64,
};

pub const LoadedMetrics = struct {
    total_trades: usize,
    winning_trades: usize,
    losing_trades: usize,
    win_rate: f64,
    net_profit: f64,
    profit_factor: f64,
    max_drawdown: f64,
    final_equity: f64,
    total_return: f64,
};

pub const LoadedTrade = struct {
    id: usize,
    entry_time: i64,
    exit_time: i64,
    entry_price: f64,
    exit_price: f64,
    size: f64,
    side: []const u8,
    pnl: f64,
    pnl_percent: f64,
    commission: f64,
};

pub const LoadedEquityPoint = struct {
    time: i64,
    equity: f64,
};

// ============================================================================
// Result Comparison
// ============================================================================

/// Compare two loaded results
pub const ResultComparison = struct {
    allocator: std.mem.Allocator,
    result1: *const LoadedResult,
    result2: *const LoadedResult,

    pub fn init(
        allocator: std.mem.Allocator,
        result1: *const LoadedResult,
        result2: *const LoadedResult,
    ) ResultComparison {
        return .{
            .allocator = allocator,
            .result1 = result1,
            .result2 = result2,
        };
    }

    /// Compare metrics between two results
    pub fn compareMetrics(self: *const ResultComparison) MetricsComparison {
        const m1 = self.result1.metrics;
        const m2 = self.result2.metrics;

        return MetricsComparison{
            .total_return_diff = m2.total_return - m1.total_return,
            .win_rate_diff = m2.win_rate - m1.win_rate,
            .profit_factor_diff = m2.profit_factor - m1.profit_factor,
            .max_drawdown_diff = m2.max_drawdown - m1.max_drawdown,
            .net_profit_diff = m2.net_profit - m1.net_profit,
            .trade_count_diff = @as(i64, @intCast(m2.total_trades)) - @as(i64, @intCast(m1.total_trades)),
        };
    }

    /// Print comparison summary
    pub fn printSummary(self: *const ResultComparison, writer: anytype) !void {
        const comparison = self.compareMetrics();

        try writer.print("\n=== Result Comparison ===\n", .{});
        try writer.print("Strategy 1: {s}\n", .{self.result1.metadata.strategy});
        try writer.print("Strategy 2: {s}\n", .{self.result2.metadata.strategy});
        try writer.print("\nMetric Differences (Strategy2 - Strategy1):\n", .{});
        try writer.print("  Total Return:   {d:+.4}%\n", .{comparison.total_return_diff * 100});
        try writer.print("  Win Rate:       {d:+.4}%\n", .{comparison.win_rate_diff * 100});
        try writer.print("  Profit Factor:  {d:+.4}\n", .{comparison.profit_factor_diff});
        try writer.print("  Max Drawdown:   {d:+.4}%\n", .{comparison.max_drawdown_diff * 100});
        try writer.print("  Net Profit:     {d:+.2}\n", .{comparison.net_profit_diff});
        try writer.print("  Trade Count:    {d:+}\n", .{comparison.trade_count_diff});
    }
};

pub const MetricsComparison = struct {
    total_return_diff: f64,
    win_rate_diff: f64,
    profit_factor_diff: f64,
    max_drawdown_diff: f64,
    net_profit_diff: f64,
    trade_count_diff: i64,
};

// ============================================================================
// Tests
// ============================================================================

test "ResultLoader: initialization" {
    const allocator = std.testing.allocator;

    var loader = ResultLoader.init(allocator);
    defer loader.deinit();
}

test "ResultLoader: load from string" {
    const allocator = std.testing.allocator;

    var loader = ResultLoader.init(allocator);
    defer loader.deinit();

    const json =
        \\{
        \\  "metadata": {
        \\    "strategy": "dual_ma",
        \\    "pair": "BTC/USDT",
        \\    "timeframe": "h1",
        \\    "start_time": 1704067200000,
        \\    "end_time": 1704153600000,
        \\    "total_candles": 24
        \\  },
        \\  "config": {
        \\    "initial_capital": 10000.0,
        \\    "commission_rate": 0.001,
        \\    "slippage": 0.0005
        \\  },
        \\  "metrics": {
        \\    "total_trades": 5,
        \\    "winning_trades": 3,
        \\    "losing_trades": 2,
        \\    "win_rate": 0.6,
        \\    "net_profit": 500.0,
        \\    "profit_factor": 1.8,
        \\    "max_drawdown": 0.05,
        \\    "final_equity": 10500.0,
        \\    "total_return": 0.05
        \\  },
        \\  "trades": [],
        \\  "equity_curve": []
        \\}
    ;

    var result = try loader.loadFromString(json);
    defer result.deinit();

    try std.testing.expectEqualStrings("dual_ma", result.metadata.strategy);
    try std.testing.expectEqual(@as(usize, 5), result.metrics.total_trades);
    try std.testing.expectApproxEqAbs(@as(f64, 500.0), result.metrics.net_profit, 0.01);
}

test "ResultComparison: compare metrics" {
    const allocator = std.testing.allocator;

    var loader = ResultLoader.init(allocator);
    defer loader.deinit();

    const json1 =
        \\{"metadata": {"strategy": "s1", "pair": "BTC/USDT", "timeframe": "h1", "start_time": 0, "end_time": 0, "total_candles": 0},
        \\"config": {"initial_capital": 10000, "commission_rate": 0.001, "slippage": 0.0005},
        \\"metrics": {"total_trades": 10, "winning_trades": 6, "losing_trades": 4, "win_rate": 0.6, "net_profit": 500, "profit_factor": 1.5, "max_drawdown": 0.1, "final_equity": 10500, "total_return": 0.05}}
    ;

    const json2 =
        \\{"metadata": {"strategy": "s2", "pair": "BTC/USDT", "timeframe": "h1", "start_time": 0, "end_time": 0, "total_candles": 0},
        \\"config": {"initial_capital": 10000, "commission_rate": 0.001, "slippage": 0.0005},
        \\"metrics": {"total_trades": 15, "winning_trades": 10, "losing_trades": 5, "win_rate": 0.67, "net_profit": 800, "profit_factor": 2.0, "max_drawdown": 0.08, "final_equity": 10800, "total_return": 0.08}}
    ;

    var result1 = try loader.loadFromString(json1);
    defer result1.deinit();

    var result2 = try loader.loadFromString(json2);
    defer result2.deinit();

    const comparison = ResultComparison.init(allocator, &result1, &result2);
    const metrics = comparison.compareMetrics();

    try std.testing.expect(metrics.net_profit_diff > 0); // s2 is better
    try std.testing.expect(metrics.trade_count_diff > 0); // s2 has more trades
}
