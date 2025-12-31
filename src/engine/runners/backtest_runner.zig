//! Backtest Runner
//!
//! Wraps backtest execution for lifecycle management via API.
//! Provides async backtest execution with progress tracking,
//! result retrieval, and cancellation support.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import zigQuant types
const root = @import("../../root.zig");
const Decimal = root.Decimal;
const TradingPair = root.TradingPair;
const Timeframe = root.Timeframe;
const Timestamp = root.Timestamp;
const Logger = root.Logger;
const LogWriter = root.LogWriter;
const LogRecord = root.LogRecord;
const BacktestEngine = root.BacktestEngine;
const BacktestConfig = root.BacktestConfig;
const BacktestResult = root.BacktestResult;
const IStrategy = root.IStrategy;

/// Progress callback context for backtest engine
var progress_runner: ?*anyopaque = null;

fn progressCallback(prog: f64, current: usize, total: usize) void {
    if (progress_runner) |runner_ptr| {
        const runner = @as(*BacktestRunner, @ptrCast(@alignCast(runner_ptr)));
        runner.mutex.lock();
        defer runner.mutex.unlock();
        runner.progress.progress = prog;
        runner.progress.current_bar = current;
        runner.progress.total_bars = total;
    }
}

/// Create a null logger that discards all output
fn createNullLogger(allocator: Allocator) Logger {
    const NullLogWriter = struct {
        fn writeFn(_: *anyopaque, _: LogRecord) anyerror!void {}
        fn flushFn(_: *anyopaque) anyerror!void {}
        fn closeFn(_: *anyopaque) void {}
    };

    const null_writer = LogWriter{
        .ptr = undefined,
        .writeFn = NullLogWriter.writeFn,
        .flushFn = NullLogWriter.flushFn,
        .closeFn = NullLogWriter.closeFn,
    };

    return Logger.init(allocator, null_writer, .info);
}

/// Backtest request configuration (from API)
pub const BacktestRequest = struct {
    /// Strategy name
    strategy: []const u8,

    /// Strategy parameters (JSON string)
    params: ?[]const u8 = null,

    /// Trading pair
    symbol: []const u8,

    /// Timeframe (1m, 5m, 15m, 1h, 4h, 1d, etc.)
    timeframe: []const u8,

    /// Start date (ISO 8601 or timestamp)
    start_date: []const u8,

    /// End date (ISO 8601 or timestamp)
    end_date: []const u8,

    /// Initial capital
    initial_capital: f64 = 10000,

    /// Commission rate
    commission: f64 = 0.0005,

    /// Slippage
    slippage: f64 = 0.0001,

    /// Data file path (optional)
    data_file: ?[]const u8 = null,

    /// Parse timeframe string to Timeframe enum
    pub fn parseTimeframe(self: BacktestRequest) !Timeframe {
        return Timeframe.fromString(self.timeframe);
    }

    /// Parse symbol to TradingPair
    pub fn parsePair(self: BacktestRequest) TradingPair {
        // Handle formats like "BTCUSDT", "BTC-USDT", "BTC/USDT"
        var base: []const u8 = "";
        var quote: []const u8 = "";

        if (std.mem.indexOf(u8, self.symbol, "-")) |idx| {
            base = self.symbol[0..idx];
            quote = self.symbol[idx + 1 ..];
        } else if (std.mem.indexOf(u8, self.symbol, "/")) |idx| {
            base = self.symbol[0..idx];
            quote = self.symbol[idx + 1 ..];
        } else {
            // Assume format like "BTCUSDT" - try common quote currencies
            const quote_currencies = [_][]const u8{ "USDT", "USDC", "USD", "BTC", "ETH" };
            for (quote_currencies) |q| {
                if (std.mem.endsWith(u8, self.symbol, q)) {
                    base = self.symbol[0 .. self.symbol.len - q.len];
                    quote = q;
                    break;
                }
            }
        }

        if (base.len == 0) {
            base = self.symbol;
            quote = "USDT";
        }

        return .{ .base = base, .quote = quote };
    }
};

/// Backtest runner status
pub const BacktestStatus = enum {
    queued,
    running,
    completed,
    cancelled,
    failed,

    pub fn toString(self: BacktestStatus) []const u8 {
        return switch (self) {
            .queued => "queued",
            .running => "running",
            .completed => "completed",
            .cancelled => "cancelled",
            .failed => "failed",
        };
    }
};

/// Backtest progress information
pub const BacktestProgress = struct {
    progress: f64 = 0, // 0.0 to 1.0
    current_bar: usize = 0,
    total_bars: usize = 0,
    current_date: ?[]const u8 = null,
    trades_so_far: u32 = 0,
    elapsed_seconds: i64 = 0,
};

/// Backtest result summary for API
pub const BacktestResultSummary = struct {
    total_return: f64,
    sharpe_ratio: f64,
    max_drawdown: f64,
    win_rate: f64,
    profit_factor: f64,
    total_trades: u32,
    winning_trades: u32,
    losing_trades: u32,
    net_profit: f64,
    total_commission: f64,
};

/// Backtest Runner - manages a single backtest job
pub const BacktestRunner = struct {
    allocator: Allocator,
    id: []const u8,
    request: BacktestRequest,
    status: BacktestStatus,
    progress: BacktestProgress,
    result: ?*BacktestResult,
    error_message: ?[]const u8,
    start_time: i64,
    end_time: i64,

    // Threading
    thread: ?std.Thread,
    should_cancel: std.atomic.Value(bool),
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// Create a new backtest runner
    pub fn init(allocator: Allocator, id: []const u8, request: BacktestRequest) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Copy ID
        const id_copy = try allocator.dupe(u8, id);
        errdefer allocator.free(id_copy);

        // Copy request strings
        const strategy_copy = try allocator.dupe(u8, request.strategy);
        errdefer allocator.free(strategy_copy);

        const symbol_copy = try allocator.dupe(u8, request.symbol);
        errdefer allocator.free(symbol_copy);

        const timeframe_copy = try allocator.dupe(u8, request.timeframe);
        errdefer allocator.free(timeframe_copy);

        const start_date_copy = try allocator.dupe(u8, request.start_date);
        errdefer allocator.free(start_date_copy);

        const end_date_copy = try allocator.dupe(u8, request.end_date);
        errdefer allocator.free(end_date_copy);

        var params_copy: ?[]const u8 = null;
        if (request.params) |p| {
            params_copy = try allocator.dupe(u8, p);
        }

        var data_file_copy: ?[]const u8 = null;
        if (request.data_file) |df| {
            data_file_copy = try allocator.dupe(u8, df);
        }

        self.* = .{
            .allocator = allocator,
            .id = id_copy,
            .request = .{
                .strategy = strategy_copy,
                .params = params_copy,
                .symbol = symbol_copy,
                .timeframe = timeframe_copy,
                .start_date = start_date_copy,
                .end_date = end_date_copy,
                .initial_capital = request.initial_capital,
                .commission = request.commission,
                .slippage = request.slippage,
                .data_file = data_file_copy,
            },
            .status = .queued,
            .progress = .{},
            .result = null,
            .error_message = null,
            .start_time = 0,
            .end_time = 0,
            .thread = null,
            .should_cancel = std.atomic.Value(bool).init(false),
            .mutex = .{},
        };

        return self;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        // Cancel if running
        if (self.status == .running) {
            self.cancel() catch {};
        }

        // Free strings
        self.allocator.free(self.id);
        self.allocator.free(self.request.strategy);
        self.allocator.free(self.request.symbol);
        self.allocator.free(self.request.timeframe);
        self.allocator.free(self.request.start_date);
        self.allocator.free(self.request.end_date);

        if (self.request.params) |p| {
            self.allocator.free(p);
        }
        if (self.request.data_file) |df| {
            self.allocator.free(df);
        }
        if (self.error_message) |err| {
            self.allocator.free(err);
        }

        // Free result
        if (self.result) |res| {
            res.deinit();
            self.allocator.destroy(res);
        }

        self.allocator.destroy(self);
    }

    /// Start the backtest (async)
    pub fn start(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.status != .queued) {
            return error.InvalidState;
        }

        self.status = .running;
        self.start_time = std.time.timestamp();
        self.should_cancel.store(false, .release);

        // Start background thread
        self.thread = try std.Thread.spawn(.{}, runBacktest, .{self});
    }

    /// Cancel the backtest
    pub fn cancel(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.status != .running and self.status != .queued) {
            return error.InvalidState;
        }

        self.should_cancel.store(true, .release);

        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }

        self.status = .cancelled;
        self.end_time = std.time.timestamp();
    }

    /// Get current status
    pub fn getStatus(self: *Self) BacktestStatus {
        return self.status;
    }

    /// Get current progress
    pub fn getProgress(self: *Self) BacktestProgress {
        self.mutex.lock();
        defer self.mutex.unlock();

        var prog = self.progress;
        if (self.start_time > 0) {
            prog.elapsed_seconds = std.time.timestamp() - self.start_time;
        }
        return prog;
    }

    /// Get result summary (only available after completion)
    pub fn getResultSummary(self: *Self) ?BacktestResultSummary {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.result) |res| {
            const total_return = res.net_profit.div(res.config.initial_capital) catch Decimal.ZERO;

            return .{
                .total_return = total_return.toFloat(),
                .sharpe_ratio = 0, // TODO: Calculate from equity curve
                .max_drawdown = 0, // TODO: Calculate from equity curve
                .win_rate = res.win_rate,
                .profit_factor = res.profit_factor,
                .total_trades = res.total_trades,
                .winning_trades = res.winning_trades,
                .losing_trades = res.losing_trades,
                .net_profit = res.net_profit.toFloat(),
                .total_commission = res.calculateTotalCommission().toFloat(),
            };
        }
        return null;
    }

    /// Background thread function
    fn runBacktest(self: *Self) void {
        self.executeBacktest() catch |err| {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.status = .failed;
            self.end_time = std.time.timestamp();
            self.error_message = self.allocator.dupe(u8, @errorName(err)) catch null;
        };
    }

    /// Execute the backtest
    fn executeBacktest(self: *Self) !void {
        // Check for cancellation
        if (self.should_cancel.load(.acquire)) {
            return;
        }

        // Parse configuration
        const pair = self.request.parsePair();
        const timeframe = try self.request.parseTimeframe();

        // Parse dates (simple timestamp parsing)
        const start_ts = try parseDateToTimestamp(self.request.start_date);
        const end_ts = try parseDateToTimestamp(self.request.end_date);

        // Create backtest config
        const config = BacktestConfig{
            .pair = pair,
            .timeframe = timeframe,
            .start_time = .{ .millis = start_ts },
            .end_time = .{ .millis = end_ts },
            .initial_capital = Decimal.fromFloat(self.request.initial_capital),
            .commission_rate = Decimal.fromFloat(self.request.commission),
            .slippage = Decimal.fromFloat(self.request.slippage),
            .data_file = self.request.data_file,
        };

        // Create a null writer for the logger (we don't need logs during API backtests)
        const logger = createNullLogger(self.allocator);

        // Create backtest engine
        var engine = BacktestEngine.init(self.allocator, logger);

        // Load strategy
        const strategy = try self.loadStrategy();

        // Update progress
        {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.progress.progress = 0.1;
        }

        // Check for cancellation
        if (self.should_cancel.load(.acquire)) {
            return;
        }

        // Set global progress callback context
        progress_runner = self;

        // Run backtest with progress callback
        var result = try engine.run(strategy, config, progressCallback);

        // Check for cancellation
        if (self.should_cancel.load(.acquire)) {
            result.deinit();
            return;
        }

        // Store result
        {
            self.mutex.lock();
            defer self.mutex.unlock();

            const result_ptr = try self.allocator.create(BacktestResult);
            result_ptr.* = result;
            self.result = result_ptr;

            self.progress.progress = 1.0;
            self.progress.trades_so_far = result.total_trades;
            self.status = .completed;
            self.end_time = std.time.timestamp();
        }
    }

    /// Load strategy by name using StrategyFactory
    fn loadStrategy(self: *Self) !IStrategy {
        const root_mod = @import("../../root.zig");
        var factory = root_mod.StrategyFactory.init(self.allocator);

        // Build config JSON based on request
        var json_buf: [4096]u8 = undefined;

        // Default pair if needed
        const pair = self.request.parsePair();

        const json = std.fmt.bufPrint(&json_buf,
            \\{{
            \\  "strategy": "{s}",
            \\  "pair": {{ "base": "{s}", "quote": "{s}" }},
            \\  "parameters": {s}
            \\}}
        , .{
            self.request.strategy,
            pair.base,
            pair.quote,
            self.request.params orelse "{}",
        }) catch return error.ConfigBuildFailed;

        const wrapper = factory.create(self.request.strategy, json) catch {
            return error.StrategyNotFound;
        };

        // Store wrapper for cleanup
        // Note: In a full implementation, we'd store this wrapper
        // For now, just return the interface
        return wrapper.interface;
    }
};

/// Parse date string to milliseconds timestamp
fn parseDateToTimestamp(date_str: []const u8) !i64 {
    // Try parsing as ISO 8601 date (YYYY-MM-DD)
    if (date_str.len >= 10 and date_str[4] == '-' and date_str[7] == '-') {
        const year = std.fmt.parseInt(i32, date_str[0..4], 10) catch return error.InvalidDate;
        const month = std.fmt.parseInt(u8, date_str[5..7], 10) catch return error.InvalidDate;
        const day = std.fmt.parseInt(u8, date_str[8..10], 10) catch return error.InvalidDate;

        // Simple approximation (not accounting for leap years properly)
        const days_per_month = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var total_days: i64 = 0;

        // Days from years since 1970
        total_days += (@as(i64, year) - 1970) * 365;
        // Add leap years
        total_days += @divTrunc((@as(i64, year) - 1969), 4);

        // Days from months
        for (0..month - 1) |m| {
            total_days += days_per_month[m];
        }

        // Days
        total_days += day - 1;

        return total_days * 24 * 60 * 60 * 1000;
    }

    // Try parsing as timestamp (milliseconds)
    if (std.fmt.parseInt(i64, date_str, 10)) |ts| {
        return ts;
    } else |_| {
        return error.InvalidDate;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "BacktestRequest parsePair" {
    const req1 = BacktestRequest{
        .strategy = "dual_ma",
        .symbol = "BTC-USDT",
        .timeframe = "1h",
        .start_date = "2024-01-01",
        .end_date = "2024-12-31",
    };
    const pair1 = req1.parsePair();
    try std.testing.expectEqualStrings("BTC", pair1.base);
    try std.testing.expectEqualStrings("USDT", pair1.quote);

    const req2 = BacktestRequest{
        .strategy = "dual_ma",
        .symbol = "ETHUSDC",
        .timeframe = "1h",
        .start_date = "2024-01-01",
        .end_date = "2024-12-31",
    };
    const pair2 = req2.parsePair();
    try std.testing.expectEqualStrings("ETH", pair2.base);
    try std.testing.expectEqualStrings("USDC", pair2.quote);
}

test "parseDateToTimestamp" {
    const ts = try parseDateToTimestamp("2024-01-01");
    try std.testing.expect(ts > 0);

    // 2024-01-01 should be approximately 54 years * 365 days * 24 * 60 * 60 * 1000
    const expected_approx: i64 = 54 * 365 * 24 * 60 * 60 * 1000;
    try std.testing.expect(ts > expected_approx - 100 * 24 * 60 * 60 * 1000);
    try std.testing.expect(ts < expected_approx + 100 * 24 * 60 * 60 * 1000);
}
