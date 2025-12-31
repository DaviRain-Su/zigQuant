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

/// Chunked data iterator for memory-efficient processing of large datasets
pub const ChunkedDataIterator = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    file_path: []const u8,
    pair: TradingPair,
    timeframe: Timeframe,
    chunk_size: usize,
    file: ?std.fs.File = null,
    buffer: [1024 * 1024]u8 = undefined, // 1MB buffer
    current_pos: usize = 0,
    header_skipped: bool = false,
    line_num: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        logger: Logger,
        file_path: []const u8,
        pair: TradingPair,
        timeframe: Timeframe,
        chunk_size: usize,
    ) !*ChunkedDataIterator {
        const self = try allocator.create(ChunkedDataIterator);
        errdefer allocator.destroy(self);

        const file_path_copy = try allocator.dupe(u8, file_path);
        errdefer allocator.free(file_path_copy);

        self.* = .{
            .allocator = allocator,
            .logger = logger,
            .file_path = file_path_copy,
            .pair = pair,
            .timeframe = timeframe,
            .chunk_size = chunk_size,
        };

        // Open file
        self.file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            @constCast(&logger).err("Failed to open file: {s}", .{file_path}) catch {};
            return if (err == error.FileNotFound)
                BacktestError.FileNotFound
            else
                BacktestError.DataFeedError;
        };

        return self;
    }

    pub fn deinit(self: *ChunkedDataIterator) void {
        if (self.file) |file| file.close();
        self.allocator.free(self.file_path);
        self.allocator.destroy(self);
    }

    /// Get next chunk of candles
    pub fn nextChunk(self: *ChunkedDataIterator) !?Candles {
        if (self.file == null) return null;

        // Seek to current position
        try self.file.?.seekTo(self.current_pos);

        var candle_list = try std.ArrayList(Candle).initCapacity(self.allocator, self.chunk_size);
        errdefer candle_list.deinit(self.allocator);

        var candles_loaded: usize = 0;

        // Read a chunk of data
        const bytes_read = try self.file.?.read(&self.buffer);
        if (bytes_read == 0) {
            candle_list.deinit(self.allocator);
            return null;
        }

        const buffer_slice = self.buffer[0..bytes_read];
        var pos: usize = 0;

        while (pos < buffer_slice.len and candles_loaded < self.chunk_size) {
            // Find end of line
            var line_end = pos;
            while (line_end < buffer_slice.len and buffer_slice[line_end] != '\n') {
                line_end += 1;
            }
            if (line_end >= buffer_slice.len) break; // Partial line at end

            const line = buffer_slice[pos..line_end];
            const trimmed = std.mem.trimRight(u8, line, "\r");
            self.line_num += 1;

            // Skip empty lines
            if (trimmed.len == 0) {
                pos = line_end + 1;
                continue;
            }

            // Skip header line (only once at start)
            if (!self.header_skipped and std.mem.startsWith(u8, trimmed, "timestamp")) {
                self.header_skipped = true;
                pos = line_end + 1;
                continue;
            }

            // Parse CSV line
            const candle = self.parseCSVLine(trimmed, self.line_num) catch |err| {
                self.logger.err("Failed to parse line {}: {} - Line content: '{s}' (len={})", .{ self.line_num, err, trimmed, trimmed.len }) catch {};
                pos = line_end + 1;
                continue; // Skip bad lines
            };

            try candle_list.append(self.allocator, candle);
            candles_loaded += 1;
            pos = line_end + 1;
        }

        // Update current position
        self.current_pos += pos;

        if (candle_list.items.len == 0) {
            candle_list.deinit(self.allocator);
            return null; // No more data
        }

        // Create Candles struct for this chunk
        const candles = Candles.initWithCandles(
            self.allocator,
            self.pair,
            self.timeframe,
            try candle_list.toOwnedSlice(self.allocator),
        );
        candle_list.deinit(self.allocator);

        return candles;
    }

    /// Parse single CSV line (same as in HistoricalDataFeed)
    fn parseCSVLine(_: *ChunkedDataIterator, line: []const u8, _: usize) !Candle {
        var iter = std.mem.splitScalar(u8, line, ',');

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

        // Parse timestamp
        var timestamp_value = try std.fmt.parseInt(i64, timestamp_trimmed, 10);
        if (timestamp_value > 1_000_000_000_000_000) {
            timestamp_value = @divTrunc(timestamp_value, 1000);
        }

        return Candle{
            .timestamp = Timestamp{ .millis = timestamp_value },
            .open = try Decimal.fromString(open_trimmed),
            .high = try Decimal.fromString(high_trimmed),
            .low = try Decimal.fromString(low_trimmed),
            .close = try Decimal.fromString(close_trimmed),
            .volume = try Decimal.fromString(volume_trimmed),
        };
    }
};

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

    /// Create a chunked data iterator for memory-efficient processing
    pub fn createChunkedIterator(
        self: *HistoricalDataFeed,
        pair: TradingPair,
        timeframe: Timeframe,
        file_path: []const u8,
        chunk_size: usize,
    ) !*ChunkedDataIterator {
        return ChunkedDataIterator.init(
            self.allocator,
            self.logger,
            file_path,
            pair,
            timeframe,
            chunk_size,
        );
    }

    /// Load historical candles from CSV file
    pub fn loadFromCSV(
        self: *HistoricalDataFeed,
        file_path: []const u8,
        pair: TradingPair,
        timeframe: Timeframe,
    ) !Candles {
        try self.logger.info("Loading data from: {s}", .{file_path});

        // Open file
        var file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            self.logger.err("Failed to open file: {s}", .{file_path}) catch {};
            return if (err == error.FileNotFound)
                BacktestError.FileNotFound
            else
                BacktestError.DataFeedError;
        };
        defer file.close();

        // Read file content with buffer
        var read_buffer: [4096]u8 = undefined;
        var reader = file.reader(&read_buffer);

        // Allocate candles array list
        var candle_list = try std.ArrayList(Candle).initCapacity(self.allocator, 100);
        errdefer candle_list.deinit(self.allocator);

        var line_num: usize = 0;

        // Read line by line
        while (try reader.interface.takeDelimiter('\n')) |line| {
            line_num += 1;

            // Skip empty lines
            if (line.len == 0) continue;

            // Skip header line
            if (line_num == 1 and std.mem.startsWith(u8, line, "timestamp")) {
                continue;
            }

            // Parse CSV line
            const candle = self.parseCSVLine(line, line_num) catch |err| {
                self.logger.err("Failed to parse line {}: {}", .{ line_num, err }) catch {};
                return BacktestError.ParseError;
            };

            try candle_list.append(self.allocator, candle);
        }

        if (candle_list.items.len == 0) {
            self.logger.err("No data loaded from file", .{}) catch {};
            return BacktestError.NoData;
        }

        try self.logger.info("Loaded {} candles", .{candle_list.items.len});

        // Create Candles struct
        var candles = Candles.initWithCandles(
            self.allocator,
            pair,
            timeframe,
            try candle_list.toOwnedSlice(self.allocator),
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

        // Parse and normalize timestamp (handle both milliseconds and microseconds)
        var timestamp_value = try std.fmt.parseInt(i64, timestamp_trimmed, 10);
        // If timestamp is in microseconds (> 10^15), convert to milliseconds
        if (timestamp_value > 1_000_000_000_000_000) {
            timestamp_value = @divTrunc(timestamp_value, 1000);
        }

        return Candle{
            .timestamp = Timestamp{
                .millis = timestamp_value,
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
        custom_file: ?[]const u8,
    ) !Candles {
        // If custom file path is provided, use it directly
        if (custom_file) |file_path| {
            return try self.loadFromCSV(file_path, pair, timeframe);
        }

        // Try to find a matching data file using common naming conventions
        // Priority: 1) Full range file 2) Year-based file 3) Generic file
        var symbol_buf: [32]u8 = undefined;
        const symbol = std.fmt.bufPrint(&symbol_buf, "{s}{s}", .{ pair.base, pair.quote }) catch "BTCUSDT";

        // Map timeframe enum to string format used in filenames
        const tf_str = timeframe.toString();

        var filename_buf: [256]u8 = undefined;

        // Try pattern 1: Full historical data files (e.g., BTCUSDT_1h_2017_2025.csv)
        if (std.fmt.bufPrint(&filename_buf, "data/{s}_{s}_2017_2025.csv", .{ symbol, tf_str })) |filename| {
            if (std.fs.cwd().access(filename, .{})) |_| {
                self.logger.info("Found data file: {s}", .{filename}) catch {};
                return try self.loadFromCSV(filename, pair, timeframe);
            } else |_| {}
        } else |_| {}

        // Try pattern 2: Year-specific files (e.g., BTCUSDT_1h_2024.csv)
        if (std.fmt.bufPrint(&filename_buf, "data/{s}_{s}_2024.csv", .{ symbol, tf_str })) |filename| {
            if (std.fs.cwd().access(filename, .{})) |_| {
                self.logger.info("Found data file: {s}", .{filename}) catch {};
                return try self.loadFromCSV(filename, pair, timeframe);
            } else |_| {}
        } else |_| {}

        // Try pattern 3: Multi-year files (e.g., BTCUSDT_1h_2020_2024.csv)
        if (std.fmt.bufPrint(&filename_buf, "data/{s}_{s}_2020_2024.csv", .{ symbol, tf_str })) |filename| {
            if (std.fs.cwd().access(filename, .{})) |_| {
                self.logger.info("Found data file: {s}", .{filename}) catch {};
                return try self.loadFromCSV(filename, pair, timeframe);
            } else |_| {}
        } else |_| {}

        // Try pattern 4: Generic file (e.g., BTCUSDT_1h.csv)
        if (std.fmt.bufPrint(&filename_buf, "data/{s}_{s}.csv", .{ symbol, tf_str })) |filename| {
            if (std.fs.cwd().access(filename, .{})) |_| {
                self.logger.info("Found data file: {s}", .{filename}) catch {};
                return try self.loadFromCSV(filename, pair, timeframe);
            } else |_| {}
        } else |_| {}

        // If no pattern matched, fall back to original convention
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

        self.logger.err("No data file found. Tried multiple patterns. Last attempt: {s}", .{filename}) catch {};
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
