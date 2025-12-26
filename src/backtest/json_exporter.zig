/// JSON Exporter for Backtest Results
///
/// Exports complete backtest results to JSON format including:
/// - Metadata (strategy name, pair, timeframe, dates)
/// - Configuration (initial capital, commission, slippage)
/// - Performance metrics
/// - Trade details
/// - Equity curve

const std = @import("std");
const root = @import("../root.zig");
const export_mod = @import("export.zig");

const BacktestResult = root.BacktestResult;
const Trade = root.Trade;
const EquitySnapshot = root.EquitySnapshot;
const Decimal = root.Decimal;
const Timestamp = root.Timestamp;

const ExportOptions = export_mod.ExportOptions;
const ExportResult = export_mod.ExportResult;

// ============================================================================
// JSON Exporter
// ============================================================================

pub const JSONExporter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) JSONExporter {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *JSONExporter) void {
        _ = self;
    }

    /// Export backtest result to JSON file
    pub fn exportToFile(
        self: *JSONExporter,
        result: *const BacktestResult,
        options: ExportOptions,
    ) !ExportResult {
        // Build JSON string
        var json_buffer: std.ArrayListUnmanaged(u8) = .{};
        defer json_buffer.deinit(self.allocator);

        try self.writeJSON(result, options, json_buffer.writer(self.allocator));

        // Write to file
        const file = std.fs.cwd().createFile(options.output_path, .{}) catch |err| {
            return ExportResult{
                .success = false,
                .bytes_written = 0,
                .file_path = options.output_path,
                .error_message = @errorName(err),
            };
        };
        defer file.close();

        file.writeAll(json_buffer.items) catch |err| {
            return ExportResult{
                .success = false,
                .bytes_written = 0,
                .file_path = options.output_path,
                .error_message = @errorName(err),
            };
        };

        return ExportResult{
            .success = true,
            .bytes_written = json_buffer.items.len,
            .file_path = options.output_path,
            .error_message = null,
        };
    }

    /// Export to string (for testing)
    pub fn exportToString(
        self: *JSONExporter,
        result: *const BacktestResult,
        options: ExportOptions,
    ) ![]const u8 {
        var json_buffer: std.ArrayListUnmanaged(u8) = .{};
        try self.writeJSON(result, options, json_buffer.writer(self.allocator));
        return json_buffer.toOwnedSlice(self.allocator);
    }

    /// Write JSON to writer
    fn writeJSON(
        self: *JSONExporter,
        result: *const BacktestResult,
        options: ExportOptions,
        writer: anytype,
    ) !void {
        const indent = if (options.pretty_json) "  " else "";
        const newline = if (options.pretty_json) "\n" else "";

        try writer.writeAll("{");
        try writer.writeAll(newline);

        // Metadata section
        try self.writeMetadata(result, writer, indent, newline);
        try writer.writeAll(",");
        try writer.writeAll(newline);

        // Config section
        try self.writeConfig(result, writer, indent, newline);
        try writer.writeAll(",");
        try writer.writeAll(newline);

        // Metrics section
        try self.writeMetrics(result, writer, indent, newline);

        // Trades section (optional)
        if (options.include_trades) {
            try writer.writeAll(",");
            try writer.writeAll(newline);
            try self.writeTrades(result, writer, indent, newline);
        }

        // Equity curve section (optional)
        if (options.include_equity_curve) {
            try writer.writeAll(",");
            try writer.writeAll(newline);
            try self.writeEquityCurve(result, writer, indent, newline);
        }

        try writer.writeAll(newline);
        try writer.writeAll("}");
        try writer.writeAll(newline);
    }

    fn writeMetadata(
        self: *JSONExporter,
        result: *const BacktestResult,
        writer: anytype,
        indent: []const u8,
        newline: []const u8,
    ) !void {
        _ = self;

        try writer.print("{s}\"metadata\": {{{s}", .{ indent, newline });
        try writer.print("{s}{s}\"strategy\": \"{s}\",{s}", .{ indent, indent, result.strategy_name, newline });
        try writer.print("{s}{s}\"pair\": \"{s}/{s}\",{s}", .{ indent, indent, result.config.pair.base, result.config.pair.quote, newline });
        try writer.print("{s}{s}\"timeframe\": \"{s}\",{s}", .{ indent, indent, @tagName(result.config.timeframe), newline });

        // Format timestamps
        try writer.print("{s}{s}\"start_time\": {d},", .{ indent, indent, result.config.start_time.millis });
        try writer.writeAll(newline);
        try writer.print("{s}{s}\"end_time\": {d},", .{ indent, indent, result.config.end_time.millis });
        try writer.writeAll(newline);
        try writer.print("{s}{s}\"total_trades\": {d}", .{ indent, indent, result.total_trades });
        try writer.writeAll(newline);
        try writer.print("{s}}}", .{indent});
    }

    fn writeConfig(
        self: *JSONExporter,
        result: *const BacktestResult,
        writer: anytype,
        indent: []const u8,
        newline: []const u8,
    ) !void {
        _ = self;

        try writer.print("{s}\"config\": {{{s}", .{ indent, newline });
        try writer.print("{s}{s}\"initial_capital\": {d:.8},", .{ indent, indent, result.config.initial_capital.toFloat() });
        try writer.writeAll(newline);
        try writer.print("{s}{s}\"commission_rate\": {d:.8},", .{ indent, indent, result.config.commission_rate.toFloat() });
        try writer.writeAll(newline);
        try writer.print("{s}{s}\"slippage\": {d:.8}", .{ indent, indent, result.config.slippage.toFloat() });
        try writer.writeAll(newline);
        try writer.print("{s}}}", .{indent});
    }

    fn writeMetrics(
        self: *JSONExporter,
        result: *const BacktestResult,
        writer: anytype,
        indent: []const u8,
        newline: []const u8,
    ) !void {
        _ = self;

        try writer.print("{s}\"metrics\": {{{s}", .{ indent, newline });
        try writer.print("{s}{s}\"total_trades\": {d},", .{ indent, indent, result.trades.len });
        try writer.writeAll(newline);

        // Calculate winning/losing trades
        var winning: usize = 0;
        var losing: usize = 0;
        for (result.trades) |trade| {
            if (trade.pnl.toFloat() > 0) {
                winning += 1;
            } else if (trade.pnl.toFloat() < 0) {
                losing += 1;
            }
        }

        try writer.print("{s}{s}\"winning_trades\": {d},", .{ indent, indent, winning });
        try writer.writeAll(newline);
        try writer.print("{s}{s}\"losing_trades\": {d},", .{ indent, indent, losing });
        try writer.writeAll(newline);
        try writer.print("{s}{s}\"win_rate\": {d:.4},", .{ indent, indent, result.win_rate });
        try writer.writeAll(newline);
        try writer.print("{s}{s}\"net_profit\": {d:.8},", .{ indent, indent, result.net_profit.toFloat() });
        try writer.writeAll(newline);
        try writer.print("{s}{s}\"profit_factor\": {d:.4},", .{ indent, indent, result.profit_factor });
        try writer.writeAll(newline);

        // Calculate max drawdown from equity curve
        const max_drawdown = blk: {
            if (result.equity_curve.len == 0) break :blk 0.0;
            var peak = result.equity_curve[0].equity;
            var max_dd: f64 = 0.0;
            for (result.equity_curve) |snapshot| {
                if (snapshot.equity.cmp(peak) == .gt) {
                    peak = snapshot.equity;
                }
                const dd_val = peak.sub(snapshot.equity);
                const dd_pct = blk2: {
                    if (peak.eql(Decimal.ZERO)) break :blk2 0.0;
                    const ratio = dd_val.div(peak) catch break :blk2 0.0;
                    break :blk2 ratio.toFloat();
                };
                if (dd_pct > max_dd) max_dd = dd_pct;
            }
            break :blk max_dd;
        };
        try writer.print("{s}{s}\"max_drawdown\": {d:.4},", .{ indent, indent, max_drawdown });
        try writer.writeAll(newline);

        // Final equity
        const final_equity = result.config.initial_capital.add(result.net_profit);
        try writer.print("{s}{s}\"final_equity\": {d:.8},", .{ indent, indent, final_equity.toFloat() });
        try writer.writeAll(newline);

        // Total return
        const total_return = blk: {
            const initial = result.config.initial_capital;
            if (initial.eql(Decimal.ZERO)) break :blk 0.0;
            const ratio = final_equity.div(initial) catch break :blk 0.0;
            break :blk ratio.sub(Decimal.ONE).toFloat();
        };
        try writer.print("{s}{s}\"total_return\": {d:.6}", .{ indent, indent, total_return });
        try writer.writeAll(newline);
        try writer.print("{s}}}", .{indent});
    }

    fn writeTrades(
        self: *JSONExporter,
        result: *const BacktestResult,
        writer: anytype,
        indent: []const u8,
        newline: []const u8,
    ) !void {
        _ = self;

        try writer.print("{s}\"trades\": [", .{indent});

        if (result.trades.len == 0) {
            try writer.writeAll("]");
            return;
        }

        try writer.writeAll(newline);

        for (result.trades, 0..) |trade, i| {
            try writer.print("{s}{s}{{{s}", .{ indent, indent, newline });

            try writer.print("{s}{s}{s}\"id\": {d},", .{ indent, indent, indent, i + 1 });
            try writer.writeAll(newline);
            try writer.print("{s}{s}{s}\"entry_time\": {d},", .{ indent, indent, indent, trade.entry_time.millis });
            try writer.writeAll(newline);
            try writer.print("{s}{s}{s}\"entry_price\": {d:.8},", .{ indent, indent, indent, trade.entry_price.toFloat() });
            try writer.writeAll(newline);
            try writer.print("{s}{s}{s}\"exit_time\": {d},", .{ indent, indent, indent, trade.exit_time.millis });
            try writer.writeAll(newline);
            try writer.print("{s}{s}{s}\"exit_price\": {d:.8},", .{ indent, indent, indent, trade.exit_price.toFloat() });
            try writer.writeAll(newline);
            try writer.print("{s}{s}{s}\"size\": {d:.8},", .{ indent, indent, indent, trade.size.toFloat() });
            try writer.writeAll(newline);
            try writer.print("{s}{s}{s}\"side\": \"{s}\",", .{ indent, indent, indent, @tagName(trade.side) });
            try writer.writeAll(newline);
            try writer.print("{s}{s}{s}\"pnl\": {d:.8},", .{ indent, indent, indent, trade.pnl.toFloat() });
            try writer.writeAll(newline);

            // PnL percentage
            const pnl_pct = blk: {
                const entry_value = trade.entry_price.mul(trade.size);
                if (entry_value.eql(Decimal.ZERO)) break :blk 0.0;
                const pct = trade.pnl.div(entry_value) catch break :blk 0.0;
                break :blk pct.toFloat() * 100.0;
            };
            try writer.print("{s}{s}{s}\"pnl_percent\": {d:.4},", .{ indent, indent, indent, pnl_pct });
            try writer.writeAll(newline);

            try writer.print("{s}{s}{s}\"commission\": {d:.8}", .{ indent, indent, indent, trade.commission.toFloat() });
            try writer.writeAll(newline);

            try writer.print("{s}{s}}}", .{ indent, indent });

            if (i < result.trades.len - 1) {
                try writer.writeAll(",");
            }
            try writer.writeAll(newline);
        }

        try writer.print("{s}]", .{indent});
    }

    fn writeEquityCurve(
        self: *JSONExporter,
        result: *const BacktestResult,
        writer: anytype,
        indent: []const u8,
        newline: []const u8,
    ) !void {
        _ = self;

        try writer.print("{s}\"equity_curve\": [", .{indent});

        if (result.equity_curve.len == 0) {
            try writer.writeAll("]");
            return;
        }

        try writer.writeAll(newline);

        for (result.equity_curve, 0..) |snapshot, i| {
            try writer.print("{s}{s}{{\"time\": {d}, \"equity\": {d:.8}}}", .{
                indent,
                indent,
                snapshot.timestamp.millis,
                snapshot.equity.toFloat(),
            });

            if (i < result.equity_curve.len - 1) {
                try writer.writeAll(",");
            }
            try writer.writeAll(newline);
        }

        try writer.print("{s}]", .{indent});
    }
};

// ============================================================================
// Tests
// ============================================================================

test "JSONExporter: initialization" {
    const allocator = std.testing.allocator;

    var exporter = JSONExporter.init(allocator);
    defer exporter.deinit();
}

test "JSONExporter: export empty result" {
    const allocator = std.testing.allocator;

    // Create a minimal backtest result
    const config = root.BacktestConfig{
        .pair = root.TradingPair{ .base = "BTC", .quote = "USDT" },
        .timeframe = .h1,
        .start_time = Timestamp.fromSeconds(1704067200), // 2024-01-01
        .end_time = Timestamp.fromSeconds(1704153600), // 2024-01-02
        .initial_capital = Decimal.fromInt(10000),
        .commission_rate = Decimal.fromFloat(0.001),
        .slippage = Decimal.fromFloat(0.0005),
        .data_file = null,
    };

    var result = BacktestResult.init(allocator, config, "test_strategy");
    defer result.deinit();

    var exporter = JSONExporter.init(allocator);
    defer exporter.deinit();

    const json = try exporter.exportToString(&result, .{
        .output_path = "test.json",
        .pretty_json = true,
        .include_trades = true,
        .include_equity_curve = true,
    });
    defer allocator.free(json);

    // Verify JSON structure
    try std.testing.expect(std.mem.indexOf(u8, json, "\"metadata\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"config\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"metrics\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"trades\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"equity_curve\"") != null);
}
