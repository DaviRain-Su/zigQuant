/// CSV Exporter for Backtest Results
///
/// Exports backtest data to CSV format:
/// - Trade details (entry/exit times, prices, PnL)
/// - Equity curve data (timestamp, equity, drawdown)

const std = @import("std");
const root = @import("../root.zig");
const export_mod = @import("export.zig");

const Trade = root.Trade;
const EquitySnapshot = root.EquitySnapshot;
const Decimal = root.Decimal;
const Timestamp = root.Timestamp;

const ExportResult = export_mod.ExportResult;

// ============================================================================
// CSV Exporter
// ============================================================================

pub const CSVExporter = struct {
    allocator: std.mem.Allocator,

    /// CSV delimiter (comma by default)
    delimiter: u8 = ',',

    /// Quote character for text fields
    quote_char: u8 = '"',

    pub fn init(allocator: std.mem.Allocator) CSVExporter {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CSVExporter) void {
        _ = self;
    }

    /// Export trades to CSV file
    pub fn exportTrades(
        self: *CSVExporter,
        trades: []const Trade,
        output_path: []const u8,
    ) !ExportResult {
        const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
            return ExportResult{
                .success = false,
                .bytes_written = 0,
                .file_path = output_path,
                .error_message = @errorName(err),
            };
        };
        defer file.close();

        var buffered = std.io.bufferedWriter(file.writer());
        const writer = buffered.writer();

        // Write header
        try writer.writeAll("id,entry_time,entry_price,exit_time,exit_price,size,side,pnl,pnl_percent,commission\n");

        // Write trade rows
        for (trades, 0..) |trade, i| {
            try self.writeTradeRow(writer, trade, i + 1);
        }

        try buffered.flush();

        return ExportResult{
            .success = true,
            .bytes_written = 0, // Approximate
            .file_path = output_path,
            .error_message = null,
        };
    }

    /// Export trades to string (for testing)
    pub fn exportTradesToString(
        self: *CSVExporter,
        trades: []const Trade,
    ) ![]const u8 {
        var buffer: std.ArrayListUnmanaged(u8) = .{};
        errdefer buffer.deinit(self.allocator);

        const writer = buffer.writer(self.allocator);

        // Write header
        try writer.writeAll("id,entry_time,entry_price,exit_time,exit_price,size,side,pnl,pnl_percent,commission\n");

        // Write trade rows
        for (trades, 0..) |trade, i| {
            try self.writeTradeRow(writer, trade, i + 1);
        }

        return buffer.toOwnedSlice(self.allocator);
    }

    fn writeTradeRow(self: *CSVExporter, writer: anytype, trade: Trade, id: usize) !void {
        _ = self;

        // Calculate PnL percentage
        const pnl_pct = blk: {
            const entry_value = trade.entry_price.mul(trade.size);
            if (entry_value.eql(Decimal.ZERO)) break :blk 0.0;
            const pct = trade.pnl.div(entry_value) catch break :blk 0.0;
            break :blk pct.toFloat() * 100.0;
        };

        try writer.print("{d},{d},{d:.8},{d},{d:.8},{d:.8},{s},{d:.8},{d:.4},{d:.8}\n", .{
            id,
            trade.entry_time.millis,
            trade.entry_price.toFloat(),
            trade.exit_time.millis,
            trade.exit_price.toFloat(),
            trade.size.toFloat(),
            @tagName(trade.side),
            trade.pnl.toFloat(),
            pnl_pct,
            trade.commission.toFloat(),
        });
    }

    /// Export equity curve to CSV file
    pub fn exportEquityCurve(
        self: *CSVExporter,
        equity_curve: []const EquitySnapshot,
        output_path: []const u8,
    ) !ExportResult {
        const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
            return ExportResult{
                .success = false,
                .bytes_written = 0,
                .file_path = output_path,
                .error_message = @errorName(err),
            };
        };
        defer file.close();

        var buffered = std.io.bufferedWriter(file.writer());
        const writer = buffered.writer();

        // Write header
        try writer.writeAll("timestamp,equity,drawdown\n");

        // Calculate drawdowns and write rows
        var peak = if (equity_curve.len > 0) equity_curve[0].equity else Decimal.ZERO;

        for (equity_curve) |snapshot| {
            try self.writeEquityRow(writer, snapshot, &peak);
        }

        try buffered.flush();

        return ExportResult{
            .success = true,
            .bytes_written = 0,
            .file_path = output_path,
            .error_message = null,
        };
    }

    /// Export equity curve to string (for testing)
    pub fn exportEquityCurveToString(
        self: *CSVExporter,
        equity_curve: []const EquitySnapshot,
    ) ![]const u8 {
        var buffer: std.ArrayListUnmanaged(u8) = .{};
        errdefer buffer.deinit(self.allocator);

        const writer = buffer.writer(self.allocator);

        // Write header
        try writer.writeAll("timestamp,equity,drawdown\n");

        // Calculate drawdowns and write rows
        var peak = if (equity_curve.len > 0) equity_curve[0].equity else Decimal.ZERO;

        for (equity_curve) |snapshot| {
            try self.writeEquityRow(writer, snapshot, &peak);
        }

        return buffer.toOwnedSlice(self.allocator);
    }

    fn writeEquityRow(
        self: *CSVExporter,
        writer: anytype,
        snapshot: EquitySnapshot,
        peak: *Decimal,
    ) !void {
        _ = self;

        // Update peak
        if (snapshot.equity.cmp(peak.*) == .gt) {
            peak.* = snapshot.equity;
        }

        // Calculate drawdown
        const drawdown = blk: {
            if (peak.eql(Decimal.ZERO)) break :blk 0.0;
            const dd = peak.sub(snapshot.equity);
            const ratio = dd.div(peak.*) catch break :blk 0.0;
            break :blk ratio.toFloat();
        };

        try writer.print("{d},{d:.8},{d:.6}\n", .{
            snapshot.timestamp.millis,
            snapshot.equity.toFloat(),
            drawdown,
        });
    }

    /// Escape a string for CSV (handle quotes and special chars)
    pub fn escapeCSV(self: *CSVExporter, input: []const u8) ![]const u8 {
        // Check if escaping is needed
        var needs_escape = false;
        for (input) |c| {
            if (c == self.delimiter or c == self.quote_char or c == '\n' or c == '\r') {
                needs_escape = true;
                break;
            }
        }

        if (!needs_escape) {
            return try self.allocator.dupe(u8, input);
        }

        // Escape by wrapping in quotes and doubling any existing quotes
        var result: std.ArrayListUnmanaged(u8) = .{};
        errdefer result.deinit(self.allocator);

        try result.append(self.allocator, self.quote_char);
        for (input) |c| {
            if (c == self.quote_char) {
                try result.append(self.allocator, self.quote_char);
            }
            try result.append(self.allocator, c);
        }
        try result.append(self.allocator, self.quote_char);

        return result.toOwnedSlice(self.allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "CSVExporter: initialization" {
    const allocator = std.testing.allocator;

    var exporter = CSVExporter.init(allocator);
    defer exporter.deinit();
}

test "CSVExporter: export empty trades" {
    const allocator = std.testing.allocator;

    var exporter = CSVExporter.init(allocator);
    defer exporter.deinit();

    const trades: []const Trade = &.{};
    const csv = try exporter.exportTradesToString(trades);
    defer allocator.free(csv);

    // Should only have header
    try std.testing.expectEqualStrings("id,entry_time,entry_price,exit_time,exit_price,size,side,pnl,pnl_percent,commission\n", csv);
}

test "CSVExporter: export trades" {
    const allocator = std.testing.allocator;

    var exporter = CSVExporter.init(allocator);
    defer exporter.deinit();

    const trades = [_]Trade{
        .{
            .id = 1,
            .pair = root.TradingPair{ .base = "BTC", .quote = "USDT" },
            .entry_time = Timestamp.fromMillis(1704067200000),
            .exit_time = Timestamp.fromMillis(1704153600000),
            .entry_price = Decimal.fromInt(42000),
            .exit_price = Decimal.fromInt(43000),
            .size = Decimal.fromFloat(0.1),
            .side = .long,
            .pnl = Decimal.fromInt(100),
            .pnl_percent = Decimal.fromFloat(2.38),
            .commission = Decimal.fromFloat(0.84),
            .duration_minutes = 1440,
        },
    };

    const csv = try exporter.exportTradesToString(&trades);
    defer allocator.free(csv);

    // Should have header + 1 data row
    var lines = std.mem.splitScalar(u8, csv, '\n');
    _ = lines.next(); // Header
    const data_line = lines.next();
    try std.testing.expect(data_line != null);
    try std.testing.expect(std.mem.indexOf(u8, data_line.?, "long") != null);
}

test "CSVExporter: export equity curve" {
    const allocator = std.testing.allocator;

    var exporter = CSVExporter.init(allocator);
    defer exporter.deinit();

    const equity = [_]EquitySnapshot{
        .{
            .timestamp = Timestamp.fromMillis(1704067200000),
            .equity = Decimal.fromInt(10000),
            .balance = Decimal.fromInt(10000),
            .unrealized_pnl = Decimal.ZERO,
        },
        .{
            .timestamp = Timestamp.fromMillis(1704153600000),
            .equity = Decimal.fromInt(10100),
            .balance = Decimal.fromInt(10100),
            .unrealized_pnl = Decimal.ZERO,
        },
    };

    const csv = try exporter.exportEquityCurveToString(&equity);
    defer allocator.free(csv);

    // Should have header + 2 data rows
    var lines = std.mem.splitScalar(u8, csv, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line.len > 0) count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), count);
}

test "CSVExporter: escape CSV" {
    const allocator = std.testing.allocator;

    var exporter = CSVExporter.init(allocator);
    defer exporter.deinit();

    // Simple string, no escaping needed
    const simple = try exporter.escapeCSV("hello");
    defer allocator.free(simple);
    try std.testing.expectEqualStrings("hello", simple);

    // String with comma
    const comma = try exporter.escapeCSV("hello,world");
    defer allocator.free(comma);
    try std.testing.expectEqualStrings("\"hello,world\"", comma);

    // String with quote
    const quote = try exporter.escapeCSV("say \"hello\"");
    defer allocator.free(quote);
    try std.testing.expectEqualStrings("\"say \"\"hello\"\"\"", quote);
}
