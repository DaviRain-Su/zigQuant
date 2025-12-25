//! Backtest Engine - Historical Data Feed
//!
//! Loads and validates historical candle data for backtesting.

const std = @import("std");
const Decimal = @import("../core/decimal.zig").Decimal;
const Timestamp = @import("../core/time.zig").Timestamp;
const Candle = @import("../market/candles.zig").Candle;
const Candles = @import("../market/candles.zig").Candles;
const TradingPair = @import("../exchange/types.zig").TradingPair;
const Timeframe = @import("../exchange/types.zig").Timeframe;
const Logger = @import("../core/logger.zig").Logger;
const ConsoleWriter = @import("../core/logger.zig").ConsoleWriter;
const BacktestError = @import("types.zig").BacktestError;

// ============================================================================
// Historical Data Feed
// ============================================================================

/// Historical data loading and validation
pub const HistoricalDataFeed = struct {
    allocator: std.mem.Allocator,
    logger: Logger,

    pub fn init(allocator: std.mem.Allocator, logger: Logger) HistoricalDataFeed {
        return .{
            .allocator = allocator,
            .logger = logger,
        };
    }

    /// Load historical candles from CSV file
    pub fn loadFromCSV(
        self: *HistoricalDataFeed,
        file_path: []const u8,
        pair: TradingPair,
        timeframe: Timeframe,
    ) !Candles {
        self.logger.info("Loading data from: {s}", .{file_path});

        // Open file
        var file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            self.logger.err("Failed to open file: {s}", .{file_path});
            return if (err == error.FileNotFound)
                BacktestError.FileNotFound
            else
                BacktestError.DataFeedError;
        };
        defer file.close();

        // Read file content
        var buffered = std.io.bufferedReader(file.reader());
        var reader = buffered.reader();

        // Allocate candles array list
        var candle_list = std.ArrayList(Candle).init(self.allocator);
        errdefer candle_list.deinit();

        var line_buf: [1024]u8 = undefined;
        var line_num: usize = 0;

        // Read line by line
        while (reader.readUntilDelimiterOrEof(&line_buf, '\n') catch null) |line| {
            line_num += 1;

            // Skip empty lines
            if (line.len == 0) continue;

            // Skip header line
            if (line_num == 1 and std.mem.startsWith(u8, line, "timestamp")) {
                continue;
            }

            // Parse CSV line
            const candle = self.parseCSVLine(line, line_num) catch |err| {
                self.logger.err("Failed to parse line {}: {}", .{ line_num, err });
                return BacktestError.ParseError;
            };

            try candle_list.append(candle);
        }

        if (candle_list.items.len == 0) {
            self.logger.err("No data loaded from file", .{});
            return BacktestError.NoData;
        }

        self.logger.info("Loaded {} candles", .{candle_list.items.len});

        // Create Candles struct
        var candles = Candles.initWithCandles(
            self.allocator,
            pair,
            timeframe,
            try candle_list.toOwnedSlice(),
        );

        // Validate data
        try self.validateCandles(&candles);

        return candles;
    }

    /// Parse single CSV line
    fn parseCSVLine(_: *HistoricalDataFeed, line: []const u8, _: usize) !Candle {
        var iter = std.mem.splitScalar(u8, line, ',');

        // Parse fields
        const timestamp_str = iter.next() orelse return error.MissingTimestamp;
        const open_str = iter.next() orelse return error.MissingOpen;
        const high_str = iter.next() orelse return error.MissingHigh;
        const low_str = iter.next() orelse return error.MissingLow;
        const close_str = iter.next() orelse return error.MissingClose;
        const volume_str = iter.next() orelse return error.MissingVolume;

        // Trim whitespace
        const timestamp_trimmed = std.mem.trim(u8, timestamp_str, " \t\r");
        const open_trimmed = std.mem.trim(u8, open_str, " \t\r");
        const high_trimmed = std.mem.trim(u8, high_str, " \t\r");
        const low_trimmed = std.mem.trim(u8, low_str, " \t\r");
        const close_trimmed = std.mem.trim(u8, close_str, " \t\r");
        const volume_trimmed = std.mem.trim(u8, volume_str, " \t\r");

        return Candle{
            .timestamp = Timestamp{
                .millis = try std.fmt.parseInt(i64, timestamp_trimmed, 10),
            },
            .open = try Decimal.fromString(open_trimmed),
            .high = try Decimal.fromString(high_trimmed),
            .low = try Decimal.fromString(low_trimmed),
            .close = try Decimal.fromString(close_trimmed),
            .volume = try Decimal.fromString(volume_trimmed),
        };
    }

    /// Validate candle data integrity
    fn validateCandles(self: *HistoricalDataFeed, candles: *const Candles) !void {
        if (candles.candles.len == 0) {
            return BacktestError.NoData;
        }

        try self.logger.debug("Validating {} candles", .{candles.candles.len});

        // Check each candle's OHLCV consistency
        for (candles.candles, 0..) |candle, i| {
            candle.validate() catch |err| {
                try self.logger.err("Invalid candle at index {}: {}", .{ i, err });
                return BacktestError.InvalidData;
            };
        }

        // Check time series continuity
        for (1..candles.candles.len) |i| {
            const prev = candles.candles[i - 1];
            const curr = candles.candles[i];

            // Must be sorted ascending
            if (curr.timestamp.millis <= prev.timestamp.millis) {
                try self.logger.err(
                    "Candles not sorted at index {}: {} <= {}",
                    .{ i, curr.timestamp.millis, prev.timestamp.millis },
                );
                return BacktestError.DataNotSorted;
            }
        }

        try self.logger.debug("Data validation passed", .{});
    }

    /// Load candles for specific date range
    pub fn load(
        self: *HistoricalDataFeed,
        pair: TradingPair,
        timeframe: Timeframe,
        start_time: Timestamp,
        end_time: Timestamp,
    ) !Candles {
        // For now, this is a stub that expects data to be pre-loaded in CSV files
        // In a production system, this would query a database or API

        // Construct expected filename
        var filename_buf: [256]u8 = undefined;
        const filename = try std.fmt.bufPrint(
            &filename_buf,
            "data/{s}{s}_{s}_{d}_{d}.csv",
            .{
                pair.base,
                pair.quote,
                @tagName(timeframe),
                start_time.millis,
                end_time.millis,
            },
        );

        return try self.loadFromCSV(filename, pair, timeframe);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "HistoricalDataFeed: parse CSV line" {
    const testing = std.testing;

    var log_buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&log_buf);
    const WriterType = @TypeOf(fbs.writer());
    var console = ConsoleWriter(WriterType).initWithColors(testing.allocator, fbs.writer(), false);
    defer console.deinit();
    var logger = Logger.init(testing.allocator, console.writer(), .err);
    defer logger.deinit();

    var feed = HistoricalDataFeed.init(testing.allocator, logger);

    const line = "1704067200000,2000.50,2010.75,1990.25,2005.00,1234.56";
    const candle = try feed.parseCSVLine(line, 1);

    try testing.expectEqual(@as(i64, 1704067200000), candle.timestamp.millis);
    try testing.expect(candle.open.eql(try Decimal.fromString("2000.50")));
    try testing.expect(candle.high.eql(try Decimal.fromString("2010.75")));
    try testing.expect(candle.low.eql(try Decimal.fromString("1990.25")));
    try testing.expect(candle.close.eql(try Decimal.fromString("2005.00")));
    try testing.expect(candle.volume.eql(try Decimal.fromString("1234.56")));
}

test "HistoricalDataFeed: validate sorted data" {
    const testing = std.testing;

    var log_buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&log_buf);
    const WriterType = @TypeOf(fbs.writer());
    var console = ConsoleWriter(WriterType).initWithColors(testing.allocator, fbs.writer(), false);
    defer console.deinit();
    var logger = Logger.init(testing.allocator, console.writer(), .err);
    defer logger.deinit();

    var feed = HistoricalDataFeed.init(testing.allocator, logger);

    // Create sorted candles
    const candles_data = try testing.allocator.alloc(Candle, 3);
    candles_data[0] = Candle{
        .timestamp = .{ .millis = 1000 },
        .open = Decimal.fromInt(2000),
        .high = Decimal.fromInt(2010),
        .low = Decimal.fromInt(1990),
        .close = Decimal.fromInt(2005),
        .volume = Decimal.fromInt(100),
    };
    candles_data[1] = Candle{
        .timestamp = .{ .millis = 2000 },
        .open = Decimal.fromInt(2005),
        .high = Decimal.fromInt(2015),
        .low = Decimal.fromInt(1995),
        .close = Decimal.fromInt(2010),
        .volume = Decimal.fromInt(100),
    };
    candles_data[2] = Candle{
        .timestamp = .{ .millis = 3000 },
        .open = Decimal.fromInt(2010),
        .high = Decimal.fromInt(2020),
        .low = Decimal.fromInt(2000),
        .close = Decimal.fromInt(2015),
        .volume = Decimal.fromInt(100),
    };

    var candles = Candles.initWithCandles(
        testing.allocator,
        TradingPair{ .base = "ETH", .quote = "USDC" },
        .m15,
        candles_data,
    );
    defer candles.deinit();

    // Should pass validation
    try feed.validateCandles(&candles);
}

test "HistoricalDataFeed: detect unsorted data" {
    const testing = std.testing;

    var log_buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&log_buf);
    const WriterType = @TypeOf(fbs.writer());
    var console = ConsoleWriter(WriterType).initWithColors(testing.allocator, fbs.writer(), false);
    defer console.deinit();
    var logger = Logger.init(testing.allocator, console.writer(), .err);
    defer logger.deinit();

    var feed = HistoricalDataFeed.init(testing.allocator, logger);

    // Create unsorted candles (timestamp out of order)
    const candles_data = try testing.allocator.alloc(Candle, 3);
    candles_data[0] = Candle{
        .timestamp = .{ .millis = 1000 },
        .open = Decimal.fromInt(2000),
        .high = Decimal.fromInt(2010),
        .low = Decimal.fromInt(1990),
        .close = Decimal.fromInt(2005),
        .volume = Decimal.fromInt(100),
    };
    candles_data[1] = Candle{
        .timestamp = .{ .millis = 3000 }, // Out of order!
        .open = Decimal.fromInt(2005),
        .high = Decimal.fromInt(2015),
        .low = Decimal.fromInt(1995),
        .close = Decimal.fromInt(2010),
        .volume = Decimal.fromInt(100),
    };
    candles_data[2] = Candle{
        .timestamp = .{ .millis = 2000 }, // Goes back in time!
        .open = Decimal.fromInt(2010),
        .high = Decimal.fromInt(2020),
        .low = Decimal.fromInt(2000),
        .close = Decimal.fromInt(2015),
        .volume = Decimal.fromInt(100),
    };

    var candles = Candles.initWithCandles(
        testing.allocator,
        TradingPair{ .base = "ETH", .quote = "USDC" },
        .m15,
        candles_data,
    );
    defer candles.deinit();

    // Should fail validation
    try testing.expectError(
        BacktestError.DataNotSorted,
        feed.validateCandles(&candles),
    );
}
