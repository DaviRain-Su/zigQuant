/// Backtest Result Export Module
///
/// Provides unified interface for exporting backtest results to various formats:
/// - JSON: Complete structured result with all details
/// - CSV: Trades and equity curve data
///
/// Usage:
/// ```zig
/// var exporter = Exporter.init(allocator);
/// try exporter.exportResult(&result, .{
///     .format = .json,
///     .output_path = "results/backtest.json",
/// });
/// ```

const std = @import("std");
const root = @import("../root.zig");
const json_exporter = @import("json_exporter.zig");
const csv_exporter = @import("csv_exporter.zig");

const BacktestResult = root.BacktestResult;
const BacktestConfig = root.BacktestConfig;
const Trade = root.Trade;
const EquitySnapshot = root.EquitySnapshot;
const Decimal = root.Decimal;
const Timestamp = root.Timestamp;

// ============================================================================
// Export Types
// ============================================================================

/// Supported export formats
pub const ExportFormat = enum {
    json,
    csv_trades,
    csv_equity,

    pub fn extension(self: ExportFormat) []const u8 {
        return switch (self) {
            .json => ".json",
            .csv_trades, .csv_equity => ".csv",
        };
    }
};

/// Export options configuration
pub const ExportOptions = struct {
    /// Output file path
    output_path: []const u8,

    /// Export format
    format: ExportFormat = .json,

    /// Pretty print JSON (with indentation)
    pretty_json: bool = true,

    /// Include trade details in JSON export
    include_trades: bool = true,

    /// Include equity curve in JSON export
    include_equity_curve: bool = true,

    /// Decimal precision for floating point numbers
    decimal_precision: u8 = 8,

    /// Include signal metadata in trades
    include_signal_metadata: bool = false,
};

/// Export result status
pub const ExportResult = struct {
    success: bool,
    bytes_written: usize,
    file_path: []const u8,
    error_message: ?[]const u8,
};

// ============================================================================
// Exporter
// ============================================================================

/// Unified exporter for backtest results
pub const Exporter = struct {
    allocator: std.mem.Allocator,
    json_exp: json_exporter.JSONExporter,
    csv_exp: csv_exporter.CSVExporter,

    /// Initialize exporter
    pub fn init(allocator: std.mem.Allocator) Exporter {
        return .{
            .allocator = allocator,
            .json_exp = json_exporter.JSONExporter.init(allocator),
            .csv_exp = csv_exporter.CSVExporter.init(allocator),
        };
    }

    /// Deinitialize exporter
    pub fn deinit(self: *Exporter) void {
        _ = self;
    }

    /// Export backtest result to file
    pub fn exportResult(
        self: *Exporter,
        result: *const BacktestResult,
        options: ExportOptions,
    ) !ExportResult {
        return switch (options.format) {
            .json => try self.json_exp.exportToFile(result, options),
            .csv_trades => try self.csv_exp.exportTrades(result.trades, options.output_path),
            .csv_equity => try self.csv_exp.exportEquityCurve(result.equity_curve, options.output_path),
        };
    }

    /// Export to multiple formats at once
    pub fn exportMultiple(
        self: *Exporter,
        result: *const BacktestResult,
        json_path: ?[]const u8,
        trades_csv_path: ?[]const u8,
        equity_csv_path: ?[]const u8,
    ) ![]ExportResult {
        var results = std.ArrayList(ExportResult).init(self.allocator);
        errdefer results.deinit();

        if (json_path) |path| {
            const res = try self.exportResult(result, .{
                .format = .json,
                .output_path = path,
            });
            try results.append(res);
        }

        if (trades_csv_path) |path| {
            const res = try self.exportResult(result, .{
                .format = .csv_trades,
                .output_path = path,
            });
            try results.append(res);
        }

        if (equity_csv_path) |path| {
            const res = try self.exportResult(result, .{
                .format = .csv_equity,
                .output_path = path,
            });
            try results.append(res);
        }

        return results.toOwnedSlice();
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Format Decimal to string with specified precision
pub fn formatDecimal(decimal: Decimal, precision: u8) ![]const u8 {
    _ = precision;
    // Simple float conversion for now
    var buf: [64]u8 = undefined;
    const float_val = decimal.toFloat();
    const len = std.fmt.formatFloat(&buf, float_val, .{ .mode = .decimal, .precision = 8 }) catch return error.FormatError;
    return buf[0..len];
}

/// Format timestamp to ISO8601
pub fn formatTimestamp(allocator: std.mem.Allocator, ts: Timestamp) ![]const u8 {
    const seconds = ts.millis / 1000;
    const date = std.time.epoch.EpochSeconds{ .secs = seconds };
    const day = date.getEpochDay();
    const yd = day.calculateYearDay();
    const md = yd.calculateMonthDay();
    const day_secs = date.getDaySeconds();

    const buf = try allocator.alloc(u8, 24);
    _ = std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        yd.year,
        md.month.numeric(),
        md.day_index + 1,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
    }) catch return error.FormatError;

    return buf;
}

// ============================================================================
// Tests
// ============================================================================

test "ExportFormat: extension" {
    try std.testing.expectEqualStrings(".json", ExportFormat.json.extension());
    try std.testing.expectEqualStrings(".csv", ExportFormat.csv_trades.extension());
    try std.testing.expectEqualStrings(".csv", ExportFormat.csv_equity.extension());
}

test "Exporter: initialization" {
    const allocator = std.testing.allocator;

    var exporter = Exporter.init(allocator);
    defer exporter.deinit();

    // Exporter should initialize without errors
}
