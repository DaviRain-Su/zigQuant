//! 数据存储管理器
//!
//! 提供 K 线数据和回测结果的持久化存储。
//! 当前使用文件系统存储，提供类似 SQLite 的 API 接口。
//!
//! 注意: SQLite 集成因 zig-sqlite 与 Zig 0.15.2 存在兼容性问题暂时禁用。
//! build.zig.zon 中保留了 sqlite 依赖，待兼容性问题解决后可重新启用。

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const StoredCandle = types.StoredCandle;
const BacktestRecord = types.BacktestRecord;
const TradeRecord = types.TradeRecord;
const DbStats = types.DbStats;
const StorageError = types.StorageError;

/// 数据存储管理器
pub const DataStore = struct {
    allocator: Allocator,
    /// 数据库目录路径
    db_path: []const u8,
    /// 是否为内存模式
    is_memory: bool,
    /// 内存存储 (用于 :memory: 模式)
    memory_candles: std.StringHashMap(std.ArrayList(StoredCandle)),
    memory_results: std.ArrayList(BacktestRecord),
    memory_trades: std.ArrayList(TradeRecord),
    /// 下一个 ID
    next_result_id: i64,
    next_trade_id: i64,

    const Self = @This();

    /// 打开或创建数据存储
    /// db_path 可以是目录路径或 ":memory:" 表示内存模式
    pub fn open(allocator: Allocator, db_path: []const u8) !Self {
        const is_memory = std.mem.eql(u8, db_path, ":memory:");

        const self = Self{
            .allocator = allocator,
            .db_path = if (is_memory) ":memory:" else try allocator.dupe(u8, db_path),
            .is_memory = is_memory,
            .memory_candles = std.StringHashMap(std.ArrayList(StoredCandle)).init(allocator),
            .memory_results = std.ArrayList(BacktestRecord).initCapacity(allocator, 0) catch unreachable,
            .memory_trades = std.ArrayList(TradeRecord).initCapacity(allocator, 0) catch unreachable,
            .next_result_id = 1,
            .next_trade_id = 1,
        };

        // 如果不是内存模式，确保目录存在
        if (!is_memory) {
            std.fs.cwd().makePath(db_path) catch |err| {
                if (err != error.PathAlreadyExists) {
                    return err;
                }
            };
        }

        return self;
    }

    /// 关闭数据存储
    pub fn close(self: *Self) void {
        // 清理内存缓存
        var candle_iter = self.memory_candles.iterator();
        while (candle_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.memory_candles.deinit();

        for (self.memory_results.items) |*record| {
            record.deinit(self.allocator);
        }
        self.memory_results.deinit(self.allocator);

        for (self.memory_trades.items) |*trade| {
            trade.deinit(self.allocator);
        }
        self.memory_trades.deinit(self.allocator);

        if (!self.is_memory) {
            self.allocator.free(self.db_path);
        }
    }

    // ========================================================================
    // K 线数据操作
    // ========================================================================

    /// 存储 K 线数据
    pub fn storeCandles(
        self: *Self,
        symbol: []const u8,
        timeframe: []const u8,
        candles: []const StoredCandle,
    ) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ symbol, timeframe });

        if (self.is_memory) {
            // 内存模式
            const result = try self.memory_candles.getOrPut(key);
            if (!result.found_existing) {
                result.value_ptr.* = std.ArrayList(StoredCandle).initCapacity(self.allocator, 0) catch unreachable;
            } else {
                self.allocator.free(key);
            }

            // 合并并去重
            for (candles) |candle| {
                var found = false;
                for (result.value_ptr.items) |*existing| {
                    if (existing.timestamp == candle.timestamp) {
                        existing.* = candle;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    try result.value_ptr.append(self.allocator, candle);
                }
            }

            // 按时间戳排序
            std.mem.sort(StoredCandle, result.value_ptr.items, {}, struct {
                fn lessThan(_: void, a: StoredCandle, b: StoredCandle) bool {
                    return a.timestamp < b.timestamp;
                }
            }.lessThan);
        } else {
            // 文件模式
            defer self.allocator.free(key);
            try self.storeCandlesToFile(symbol, timeframe, candles);
        }
    }

    /// 加载 K 线数据
    pub fn loadCandles(
        self: *Self,
        symbol: []const u8,
        timeframe: []const u8,
        start_ts: i64,
        end_ts: i64,
    ) ![]StoredCandle {
        if (self.is_memory) {
            const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ symbol, timeframe });
            defer self.allocator.free(key);

            if (self.memory_candles.get(key)) |candles| {
                var result = std.ArrayList(StoredCandle).initCapacity(self.allocator, 0) catch unreachable;
                for (candles.items) |c| {
                    if (c.timestamp >= start_ts and c.timestamp <= end_ts) {
                        try result.append(self.allocator, c);
                    }
                }
                return try result.toOwnedSlice(self.allocator);
            }
            return &[_]StoredCandle{};
        } else {
            return try self.loadCandlesFromFile(symbol, timeframe, start_ts, end_ts);
        }
    }

    /// 获取最新时间戳
    pub fn getLatestTimestamp(
        self: *Self,
        symbol: []const u8,
        timeframe: []const u8,
    ) !?i64 {
        if (self.is_memory) {
            const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ symbol, timeframe });
            defer self.allocator.free(key);

            if (self.memory_candles.get(key)) |candles| {
                if (candles.items.len > 0) {
                    return candles.items[candles.items.len - 1].timestamp;
                }
            }
            return null;
        } else {
            const candles = try self.loadCandlesFromFile(symbol, timeframe, 0, std.math.maxInt(i64));
            defer self.allocator.free(candles);

            if (candles.len > 0) {
                return candles[candles.len - 1].timestamp;
            }
            return null;
        }
    }

    /// 删除 K 线数据
    pub fn deleteCandles(
        self: *Self,
        symbol: []const u8,
        timeframe: []const u8,
    ) !void {
        if (self.is_memory) {
            const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ symbol, timeframe });
            defer self.allocator.free(key);

            if (self.memory_candles.fetchRemove(key)) |entry| {
                self.allocator.free(entry.key);
                var val = entry.value;
                val.deinit(self.allocator);
            }
        } else {
            const file_path = try self.getCandleFilePath(symbol, timeframe);
            defer self.allocator.free(file_path);
            std.fs.cwd().deleteFile(file_path) catch {};
        }
    }

    // ========================================================================
    // 回测结果操作
    // ========================================================================

    /// 存储回测结果
    pub fn storeBacktestResult(self: *Self, record: BacktestRecord) !i64 {
        const new_record = BacktestRecord{
            .id = self.next_result_id,
            .strategy = try self.allocator.dupe(u8, record.strategy),
            .symbol = try self.allocator.dupe(u8, record.symbol),
            .timeframe = try self.allocator.dupe(u8, record.timeframe),
            .start_time = record.start_time,
            .end_time = record.end_time,
            .total_return = record.total_return,
            .sharpe_ratio = record.sharpe_ratio,
            .max_drawdown = record.max_drawdown,
            .total_trades = record.total_trades,
            .win_rate = record.win_rate,
            .params_json = if (record.params_json) |p| try self.allocator.dupe(u8, p) else null,
            .created_at = std.time.milliTimestamp(),
        };

        self.next_result_id += 1;

        if (self.is_memory) {
            try self.memory_results.append(self.allocator, new_record);
        } else {
            try self.memory_results.append(self.allocator, new_record);
            try self.saveResultsToFile();
        }

        return new_record.id;
    }

    /// 加载回测结果
    pub fn loadBacktestResults(
        self: *Self,
        strategy: ?[]const u8,
        limit: u32,
    ) ![]BacktestRecord {
        if (!self.is_memory) {
            try self.loadResultsFromFile();
        }

        var result = std.ArrayList(BacktestRecord).initCapacity(self.allocator, 0) catch unreachable;

        // 按创建时间倒序遍历
        var count: u32 = 0;
        var i = self.memory_results.items.len;
        while (i > 0 and count < limit) : (count += 1) {
            i -= 1;
            const record = self.memory_results.items[i];

            if (strategy) |s| {
                if (!std.mem.eql(u8, record.strategy, s)) continue;
            }

            try result.append(self.allocator, BacktestRecord{
                .id = record.id,
                .strategy = try self.allocator.dupe(u8, record.strategy),
                .symbol = try self.allocator.dupe(u8, record.symbol),
                .timeframe = try self.allocator.dupe(u8, record.timeframe),
                .start_time = record.start_time,
                .end_time = record.end_time,
                .total_return = record.total_return,
                .sharpe_ratio = record.sharpe_ratio,
                .max_drawdown = record.max_drawdown,
                .total_trades = record.total_trades,
                .win_rate = record.win_rate,
                .params_json = if (record.params_json) |p| try self.allocator.dupe(u8, p) else null,
                .created_at = record.created_at,
            });
        }

        return try result.toOwnedSlice(self.allocator);
    }

    /// 获取单个回测结果
    pub fn getBacktestResult(self: *Self, id: i64) !?BacktestRecord {
        if (!self.is_memory) {
            try self.loadResultsFromFile();
        }

        for (self.memory_results.items) |record| {
            if (record.id == id) {
                return BacktestRecord{
                    .id = record.id,
                    .strategy = try self.allocator.dupe(u8, record.strategy),
                    .symbol = try self.allocator.dupe(u8, record.symbol),
                    .timeframe = try self.allocator.dupe(u8, record.timeframe),
                    .start_time = record.start_time,
                    .end_time = record.end_time,
                    .total_return = record.total_return,
                    .sharpe_ratio = record.sharpe_ratio,
                    .max_drawdown = record.max_drawdown,
                    .total_trades = record.total_trades,
                    .win_rate = record.win_rate,
                    .params_json = if (record.params_json) |p| try self.allocator.dupe(u8, p) else null,
                    .created_at = record.created_at,
                };
            }
        }
        return null;
    }

    // ========================================================================
    // 交易记录操作
    // ========================================================================

    /// 存储交易记录
    pub fn storeTrades(self: *Self, backtest_id: i64, trades: []const TradeRecord) !void {
        for (trades) |trade| {
            const new_trade = TradeRecord{
                .id = self.next_trade_id,
                .backtest_id = backtest_id,
                .timestamp = trade.timestamp,
                .side = try self.allocator.dupe(u8, trade.side),
                .price = trade.price,
                .quantity = trade.quantity,
                .pnl = trade.pnl,
            };
            self.next_trade_id += 1;
            try self.memory_trades.append(self.allocator, new_trade);
        }

        if (!self.is_memory) {
            try self.saveTradesToFile();
        }
    }

    /// 加载交易记录
    pub fn loadTrades(self: *Self, backtest_id: i64) ![]TradeRecord {
        if (!self.is_memory) {
            try self.loadTradesFromFile();
        }

        var result = std.ArrayList(TradeRecord).initCapacity(self.allocator, 0) catch unreachable;

        for (self.memory_trades.items) |trade| {
            if (trade.backtest_id == backtest_id) {
                try result.append(self.allocator, TradeRecord{
                    .id = trade.id,
                    .backtest_id = trade.backtest_id,
                    .timestamp = trade.timestamp,
                    .side = try self.allocator.dupe(u8, trade.side),
                    .price = trade.price,
                    .quantity = trade.quantity,
                    .pnl = trade.pnl,
                });
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }

    // ========================================================================
    // 统计信息
    // ========================================================================

    /// 获取数据库统计
    pub fn getStats(self: *Self) DbStats {
        var candle_count: i64 = 0;
        var iter = self.memory_candles.iterator();
        while (iter.next()) |entry| {
            candle_count += @intCast(entry.value_ptr.items.len);
        }

        // 计算文件大小
        const file_size = self.calculateTotalFileSize();

        return .{
            .candle_count = candle_count,
            .result_count = @intCast(self.memory_results.items.len),
            .trade_count = @intCast(self.memory_trades.items.len),
            .file_size = file_size,
        };
    }

    /// 计算存储目录下所有文件的总大小
    fn calculateTotalFileSize(self: *Self) u64 {
        if (self.is_memory) return 0;

        var total_size: u64 = 0;

        // 打开存储目录
        var dir = std.fs.cwd().openDir(self.db_path, .{ .iterate = true }) catch return 0;
        defer dir.close();

        // 遍历目录中的所有文件
        var dir_iter = dir.iterate();
        while (dir_iter.next() catch null) |entry| {
            if (entry.kind == .file) {
                // 获取文件大小
                const stat = dir.statFile(entry.name) catch continue;
                total_size += stat.size;
            }
        }

        return total_size;
    }

    // ========================================================================
    // 文件操作 (私有)
    // ========================================================================

    fn getCandleFilePath(self: *Self, symbol: []const u8, timeframe: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/candles_{s}_{s}.json", .{ self.db_path, symbol, timeframe });
    }

    fn storeCandlesToFile(
        self: *Self,
        symbol: []const u8,
        timeframe: []const u8,
        candles: []const StoredCandle,
    ) !void {
        const file_path = try self.getCandleFilePath(symbol, timeframe);
        defer self.allocator.free(file_path);

        // 先加载现有数据
        var existing = std.ArrayList(StoredCandle).initCapacity(self.allocator, 0) catch unreachable;
        defer existing.deinit(self.allocator);

        // 尝试读取现有文件
        if (std.fs.cwd().openFile(file_path, .{})) |file| {
            defer file.close();
            const content = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch "";
            defer if (content.len > 0) self.allocator.free(content);

            // 按行解析
            var lines = std.mem.splitSequence(u8, content, "\n");
            while (lines.next()) |line| {
                if (line.len == 0) continue;
                const parsed = std.json.parseFromSlice(StoredCandle, self.allocator, line, .{}) catch continue;
                defer parsed.deinit();
                try existing.append(self.allocator, parsed.value);
            }
        } else |_| {}

        // 合并新数据
        for (candles) |candle| {
            var found = false;
            for (existing.items) |*e| {
                if (e.timestamp == candle.timestamp) {
                    e.* = candle;
                    found = true;
                    break;
                }
            }
            if (!found) {
                try existing.append(self.allocator, candle);
            }
        }

        // 排序
        std.mem.sort(StoredCandle, existing.items, {}, struct {
            fn lessThan(_: void, a: StoredCandle, b: StoredCandle) bool {
                return a.timestamp < b.timestamp;
            }
        }.lessThan);

        // 写入文件
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        var buf: [512]u8 = undefined;
        for (existing.items) |candle| {
            // 手动格式化 JSON
            const json_line = std.fmt.bufPrint(&buf, "{{\"timestamp\":{d},\"open\":{d},\"high\":{d},\"low\":{d},\"close\":{d},\"volume\":{d}}}\n", .{
                candle.timestamp,
                candle.open,
                candle.high,
                candle.low,
                candle.close,
                candle.volume,
            }) catch continue;
            file.writeAll(json_line) catch {};
        }
    }

    fn loadCandlesFromFile(
        self: *Self,
        symbol: []const u8,
        timeframe: []const u8,
        start_ts: i64,
        end_ts: i64,
    ) ![]StoredCandle {
        const file_path = try self.getCandleFilePath(symbol, timeframe);
        defer self.allocator.free(file_path);

        var result = std.ArrayList(StoredCandle).initCapacity(self.allocator, 0) catch unreachable;

        const file = std.fs.cwd().openFile(file_path, .{}) catch {
            return try result.toOwnedSlice(self.allocator);
        };
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch {
            return try result.toOwnedSlice(self.allocator);
        };
        defer self.allocator.free(content);

        var lines = std.mem.splitSequence(u8, content, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            const parsed = std.json.parseFromSlice(StoredCandle, self.allocator, line, .{}) catch continue;
            defer parsed.deinit();

            if (parsed.value.timestamp >= start_ts and parsed.value.timestamp <= end_ts) {
                try result.append(self.allocator, parsed.value);
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }

    fn saveResultsToFile(self: *Self) !void {
        const file_path = try std.fmt.allocPrint(self.allocator, "{s}/backtest_results.json", .{self.db_path});
        defer self.allocator.free(file_path);

        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        var buf: [2048]u8 = undefined;
        for (self.memory_results.items) |record| {
            // 手动格式化 JSON (处理可选的 params_json)
            const params_str = record.params_json orelse "null";
            const json_line = if (record.params_json != null)
                std.fmt.bufPrint(&buf, "{{\"id\":{d},\"strategy\":\"{s}\",\"symbol\":\"{s}\",\"timeframe\":\"{s}\",\"start_time\":{d},\"end_time\":{d},\"total_return\":{d},\"sharpe_ratio\":{d},\"max_drawdown\":{d},\"total_trades\":{d},\"win_rate\":{d},\"params_json\":\"{s}\",\"created_at\":{d}}}\n", .{
                    record.id,
                    record.strategy,
                    record.symbol,
                    record.timeframe,
                    record.start_time,
                    record.end_time,
                    record.total_return,
                    record.sharpe_ratio,
                    record.max_drawdown,
                    record.total_trades,
                    record.win_rate,
                    params_str,
                    record.created_at,
                }) catch continue
            else
                std.fmt.bufPrint(&buf, "{{\"id\":{d},\"strategy\":\"{s}\",\"symbol\":\"{s}\",\"timeframe\":\"{s}\",\"start_time\":{d},\"end_time\":{d},\"total_return\":{d},\"sharpe_ratio\":{d},\"max_drawdown\":{d},\"total_trades\":{d},\"win_rate\":{d},\"params_json\":null,\"created_at\":{d}}}\n", .{
                    record.id,
                    record.strategy,
                    record.symbol,
                    record.timeframe,
                    record.start_time,
                    record.end_time,
                    record.total_return,
                    record.sharpe_ratio,
                    record.max_drawdown,
                    record.total_trades,
                    record.win_rate,
                    record.created_at,
                }) catch continue;
            file.writeAll(json_line) catch {};
        }
    }

    fn loadResultsFromFile(self: *Self) !void {
        const file_path = try std.fmt.allocPrint(self.allocator, "{s}/backtest_results.json", .{self.db_path});
        defer self.allocator.free(file_path);

        const file = std.fs.cwd().openFile(file_path, .{}) catch return;
        defer file.close();

        // 清空现有数据
        for (self.memory_results.items) |*record| {
            record.deinit(self.allocator);
        }
        self.memory_results.clearRetainingCapacity();

        const content = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch return;
        defer self.allocator.free(content);

        const JsonRecord = struct {
            id: i64,
            strategy: []const u8,
            symbol: []const u8,
            timeframe: []const u8,
            start_time: i64,
            end_time: i64,
            total_return: f64,
            sharpe_ratio: f64,
            max_drawdown: f64,
            total_trades: i32,
            win_rate: f64,
            params_json: ?[]const u8,
            created_at: i64,
        };

        var lines = std.mem.splitSequence(u8, content, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            const parsed = std.json.parseFromSlice(JsonRecord, self.allocator, line, .{}) catch continue;
            defer parsed.deinit();

            const record = BacktestRecord{
                .id = parsed.value.id,
                .strategy = try self.allocator.dupe(u8, parsed.value.strategy),
                .symbol = try self.allocator.dupe(u8, parsed.value.symbol),
                .timeframe = try self.allocator.dupe(u8, parsed.value.timeframe),
                .start_time = parsed.value.start_time,
                .end_time = parsed.value.end_time,
                .total_return = parsed.value.total_return,
                .sharpe_ratio = parsed.value.sharpe_ratio,
                .max_drawdown = parsed.value.max_drawdown,
                .total_trades = parsed.value.total_trades,
                .win_rate = parsed.value.win_rate,
                .params_json = if (parsed.value.params_json) |p| try self.allocator.dupe(u8, p) else null,
                .created_at = parsed.value.created_at,
            };

            try self.memory_results.append(self.allocator, record);

            if (record.id >= self.next_result_id) {
                self.next_result_id = record.id + 1;
            }
        }
    }

    fn saveTradesToFile(self: *Self) !void {
        const file_path = try std.fmt.allocPrint(self.allocator, "{s}/trades.json", .{self.db_path});
        defer self.allocator.free(file_path);

        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        var buf: [512]u8 = undefined;
        for (self.memory_trades.items) |trade| {
            // 手动格式化 JSON (处理可选的 pnl)
            const json_line = if (trade.pnl) |pnl|
                std.fmt.bufPrint(&buf, "{{\"id\":{d},\"backtest_id\":{d},\"timestamp\":{d},\"side\":\"{s}\",\"price\":{d},\"quantity\":{d},\"pnl\":{d}}}\n", .{
                    trade.id,
                    trade.backtest_id,
                    trade.timestamp,
                    trade.side,
                    trade.price,
                    trade.quantity,
                    pnl,
                }) catch continue
            else
                std.fmt.bufPrint(&buf, "{{\"id\":{d},\"backtest_id\":{d},\"timestamp\":{d},\"side\":\"{s}\",\"price\":{d},\"quantity\":{d},\"pnl\":null}}\n", .{
                    trade.id,
                    trade.backtest_id,
                    trade.timestamp,
                    trade.side,
                    trade.price,
                    trade.quantity,
                }) catch continue;
            file.writeAll(json_line) catch {};
        }
    }

    fn loadTradesFromFile(self: *Self) !void {
        const file_path = try std.fmt.allocPrint(self.allocator, "{s}/trades.json", .{self.db_path});
        defer self.allocator.free(file_path);

        const file = std.fs.cwd().openFile(file_path, .{}) catch return;
        defer file.close();

        // 清空现有数据
        for (self.memory_trades.items) |*trade| {
            trade.deinit(self.allocator);
        }
        self.memory_trades.clearRetainingCapacity();

        const content = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch return;
        defer self.allocator.free(content);

        const JsonTrade = struct {
            id: i64,
            backtest_id: i64,
            timestamp: i64,
            side: []const u8,
            price: f64,
            quantity: f64,
            pnl: ?f64,
        };

        var lines = std.mem.splitSequence(u8, content, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            const parsed = std.json.parseFromSlice(JsonTrade, self.allocator, line, .{}) catch continue;
            defer parsed.deinit();

            const trade = TradeRecord{
                .id = parsed.value.id,
                .backtest_id = parsed.value.backtest_id,
                .timestamp = parsed.value.timestamp,
                .side = try self.allocator.dupe(u8, parsed.value.side),
                .price = parsed.value.price,
                .quantity = parsed.value.quantity,
                .pnl = parsed.value.pnl,
            };

            try self.memory_trades.append(self.allocator, trade);

            if (trade.id >= self.next_trade_id) {
                self.next_trade_id = trade.id + 1;
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "DataStore: memory mode candles" {
    const allocator = std.testing.allocator;

    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    const candles = [_]StoredCandle{
        .{ .timestamp = 1000, .open = 100.0, .high = 105.0, .low = 99.0, .close = 103.0, .volume = 1000.0 },
        .{ .timestamp = 2000, .open = 103.0, .high = 108.0, .low = 101.0, .close = 106.0, .volume = 1500.0 },
    };

    try store.storeCandles("ETH", "1h", &candles);

    const loaded = try store.loadCandles("ETH", "1h", 0, 3000);
    defer allocator.free(loaded);

    try std.testing.expectEqual(@as(usize, 2), loaded.len);
    try std.testing.expectEqual(@as(i64, 1000), loaded[0].timestamp);
    try std.testing.expectEqual(@as(i64, 2000), loaded[1].timestamp);
}

test "DataStore: candle range query" {
    const allocator = std.testing.allocator;

    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    const candles = [_]StoredCandle{
        .{ .timestamp = 1000, .open = 100.0, .high = 105.0, .low = 99.0, .close = 103.0, .volume = 1000.0 },
        .{ .timestamp = 2000, .open = 103.0, .high = 108.0, .low = 101.0, .close = 106.0, .volume = 1500.0 },
        .{ .timestamp = 3000, .open = 106.0, .high = 110.0, .low = 104.0, .close = 109.0, .volume = 2000.0 },
    };

    try store.storeCandles("ETH", "1h", &candles);

    // 范围查询
    const loaded = try store.loadCandles("ETH", "1h", 1500, 2500);
    defer allocator.free(loaded);

    try std.testing.expectEqual(@as(usize, 1), loaded.len);
    try std.testing.expectEqual(@as(i64, 2000), loaded[0].timestamp);
}

test "DataStore: latest timestamp" {
    const allocator = std.testing.allocator;

    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    // 空存储
    const empty_ts = try store.getLatestTimestamp("ETH", "1h");
    try std.testing.expect(empty_ts == null);

    const candles = [_]StoredCandle{
        .{ .timestamp = 1000, .open = 100.0, .high = 105.0, .low = 99.0, .close = 103.0, .volume = 1000.0 },
        .{ .timestamp = 3000, .open = 106.0, .high = 110.0, .low = 104.0, .close = 109.0, .volume = 2000.0 },
    };

    try store.storeCandles("ETH", "1h", &candles);

    const latest = try store.getLatestTimestamp("ETH", "1h");
    try std.testing.expect(latest != null);
    try std.testing.expectEqual(@as(i64, 3000), latest.?);
}

test "DataStore: backtest results" {
    const allocator = std.testing.allocator;

    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    const id = try store.storeBacktestResult(.{
        .strategy = "dual_ma",
        .symbol = "ETH",
        .timeframe = "1h",
        .start_time = 0,
        .end_time = 86400000,
        .total_return = 0.15,
        .sharpe_ratio = 2.5,
        .max_drawdown = 0.08,
        .total_trades = 42,
        .win_rate = 0.65,
    });

    try std.testing.expectEqual(@as(i64, 1), id);

    const results = try store.loadBacktestResults(null, 10);
    defer {
        for (results) |*r| {
            var record = r.*;
            record.deinit(allocator);
        }
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("dual_ma", results[0].strategy);
}

test "DataStore: filter by strategy" {
    const allocator = std.testing.allocator;

    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    _ = try store.storeBacktestResult(.{
        .strategy = "dual_ma",
        .symbol = "ETH",
        .timeframe = "1h",
        .start_time = 0,
        .end_time = 86400000,
        .total_return = 0.15,
        .sharpe_ratio = 2.5,
        .max_drawdown = 0.08,
        .total_trades = 42,
        .win_rate = 0.65,
    });

    _ = try store.storeBacktestResult(.{
        .strategy = "rsi_mean_reversion",
        .symbol = "BTC",
        .timeframe = "4h",
        .start_time = 0,
        .end_time = 86400000,
        .total_return = 0.20,
        .sharpe_ratio = 3.0,
        .max_drawdown = 0.05,
        .total_trades = 30,
        .win_rate = 0.70,
    });

    const all_results = try store.loadBacktestResults(null, 10);
    defer {
        for (all_results) |*r| {
            var record = r.*;
            record.deinit(allocator);
        }
        allocator.free(all_results);
    }
    try std.testing.expectEqual(@as(usize, 2), all_results.len);

    const dual_ma_results = try store.loadBacktestResults("dual_ma", 10);
    defer {
        for (dual_ma_results) |*r| {
            var record = r.*;
            record.deinit(allocator);
        }
        allocator.free(dual_ma_results);
    }
    try std.testing.expectEqual(@as(usize, 1), dual_ma_results.len);
    try std.testing.expectEqualStrings("dual_ma", dual_ma_results[0].strategy);
}

test "DataStore: trades" {
    const allocator = std.testing.allocator;

    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    const backtest_id = try store.storeBacktestResult(.{
        .strategy = "dual_ma",
        .symbol = "ETH",
        .timeframe = "1h",
        .start_time = 0,
        .end_time = 86400000,
        .total_return = 0.15,
        .sharpe_ratio = 2.5,
        .max_drawdown = 0.08,
        .total_trades = 2,
        .win_rate = 0.50,
    });

    const trades = [_]TradeRecord{
        .{ .backtest_id = backtest_id, .timestamp = 1000, .side = "buy", .price = 100.0, .quantity = 1.0, .pnl = null },
        .{ .backtest_id = backtest_id, .timestamp = 2000, .side = "sell", .price = 110.0, .quantity = 1.0, .pnl = 10.0 },
    };

    try store.storeTrades(backtest_id, &trades);

    const loaded = try store.loadTrades(backtest_id);
    defer {
        for (loaded) |*t| {
            var trade = t.*;
            trade.deinit(allocator);
        }
        allocator.free(loaded);
    }

    try std.testing.expectEqual(@as(usize, 2), loaded.len);
    try std.testing.expectEqualStrings("buy", loaded[0].side);
    try std.testing.expectEqualStrings("sell", loaded[1].side);
}

test "DataStore: stats" {
    const allocator = std.testing.allocator;

    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    var stats = store.getStats();
    try std.testing.expectEqual(@as(i64, 0), stats.candle_count);
    try std.testing.expectEqual(@as(i64, 0), stats.result_count);

    const candles = [_]StoredCandle{
        .{ .timestamp = 1000, .open = 100.0, .high = 105.0, .low = 99.0, .close = 103.0, .volume = 1000.0 },
        .{ .timestamp = 2000, .open = 103.0, .high = 108.0, .low = 101.0, .close = 106.0, .volume = 1500.0 },
    };
    try store.storeCandles("ETH", "1h", &candles);

    _ = try store.storeBacktestResult(.{
        .strategy = "test",
        .symbol = "ETH",
        .timeframe = "1h",
        .start_time = 0,
        .end_time = 86400000,
        .total_return = 0.15,
        .sharpe_ratio = 2.5,
        .max_drawdown = 0.08,
        .total_trades = 10,
        .win_rate = 0.50,
    });

    stats = store.getStats();
    try std.testing.expectEqual(@as(i64, 2), stats.candle_count);
    try std.testing.expectEqual(@as(i64, 1), stats.result_count);
}

test "DataStore: candle deduplication" {
    const allocator = std.testing.allocator;

    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    // 存储初始数据
    const candles1 = [_]StoredCandle{
        .{ .timestamp = 1000, .open = 100.0, .high = 105.0, .low = 99.0, .close = 103.0, .volume = 1000.0 },
    };
    try store.storeCandles("ETH", "1h", &candles1);

    // 存储重复时间戳的数据 (应该更新)
    const candles2 = [_]StoredCandle{
        .{ .timestamp = 1000, .open = 101.0, .high = 106.0, .low = 100.0, .close = 104.0, .volume = 1100.0 },
        .{ .timestamp = 2000, .open = 104.0, .high = 109.0, .low = 102.0, .close = 107.0, .volume = 1200.0 },
    };
    try store.storeCandles("ETH", "1h", &candles2);

    const loaded = try store.loadCandles("ETH", "1h", 0, 3000);
    defer allocator.free(loaded);

    try std.testing.expectEqual(@as(usize, 2), loaded.len);
    // 第一条应该被更新
    try std.testing.expectEqual(@as(f64, 101.0), loaded[0].open);
}
