//! 内存映射数据加载模块
//!
//! 使用 mmap 高效加载大型历史数据文件。
//! 支持 CSV 格式，提供跨平台回退方案。

const std = @import("std");
const Allocator = std.mem.Allocator;
const posix = std.posix;

/// 向量化 K 线数据 (使用 f64 便于 SIMD 计算)
pub const VecCandle = struct {
    timestamp: i64,
    open: f64,
    high: f64,
    low: f64,
    close: f64,
    volume: f64,
};

/// 数据集 - 列式存储便于 SIMD 处理
pub const DataSet = struct {
    allocator: Allocator,
    len: usize,

    /// 列式存储
    timestamps: []i64,
    opens: []f64,
    highs: []f64,
    lows: []f64,
    closes: []f64,
    volumes: []f64,

    /// mmap 映射的原始数据 (如果使用 mmap)
    mapped_data: ?[]align(4096) u8 = null,

    const Self = @This();

    /// 初始化空数据集
    pub fn init(allocator: Allocator, capacity: usize) !Self {
        return .{
            .allocator = allocator,
            .len = 0,
            .timestamps = try allocator.alloc(i64, capacity),
            .opens = try allocator.alloc(f64, capacity),
            .highs = try allocator.alloc(f64, capacity),
            .lows = try allocator.alloc(f64, capacity),
            .closes = try allocator.alloc(f64, capacity),
            .volumes = try allocator.alloc(f64, capacity),
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        if (self.mapped_data) |data| {
            posix.munmap(data);
        }

        self.allocator.free(self.timestamps);
        self.allocator.free(self.opens);
        self.allocator.free(self.highs);
        self.allocator.free(self.lows);
        self.allocator.free(self.closes);
        self.allocator.free(self.volumes);
    }

    /// 获取指定索引的 K 线
    pub fn getCandle(self: *const Self, index: usize) ?VecCandle {
        if (index >= self.len) return null;

        return .{
            .timestamp = self.timestamps[index],
            .open = self.opens[index],
            .high = self.highs[index],
            .low = self.lows[index],
            .close = self.closes[index],
            .volume = self.volumes[index],
        };
    }

    /// 获取收盘价数组 (用于指标计算)
    pub fn getCloses(self: *const Self) []const f64 {
        return self.closes[0..self.len];
    }

    /// 获取开盘价数组
    pub fn getOpens(self: *const Self) []const f64 {
        return self.opens[0..self.len];
    }

    /// 获取最高价数组
    pub fn getHighs(self: *const Self) []const f64 {
        return self.highs[0..self.len];
    }

    /// 获取最低价数组
    pub fn getLows(self: *const Self) []const f64 {
        return self.lows[0..self.len];
    }

    /// 获取成交量数组
    pub fn getVolumes(self: *const Self) []const f64 {
        return self.volumes[0..self.len];
    }
};

/// 内存映射数据加载器
pub const MmapDataLoader = struct {
    allocator: Allocator,
    use_mmap: bool,

    const Self = @This();

    pub fn init(allocator: Allocator, use_mmap: bool) Self {
        return .{
            .allocator = allocator,
            .use_mmap = use_mmap,
        };
    }

    /// 加载 CSV 文件
    /// 格式: timestamp,open,high,low,close,volume
    pub fn loadCsv(self: *Self, path: []const u8) !DataSet {
        if (self.use_mmap) {
            return self.loadCsvMmap(path);
        } else {
            return self.loadCsvStandard(path);
        }
    }

    /// 使用 mmap 加载 CSV
    fn loadCsvMmap(self: *Self, path: []const u8) !DataSet {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        const file_size = stat.size;

        if (file_size == 0) {
            return DataSet.init(self.allocator, 0);
        }

        // 内存映射文件
        const mapped = try posix.mmap(
            null,
            file_size,
            posix.PROT.READ,
            .{ .TYPE = .PRIVATE },
            file.handle,
            0,
        );

        // 估算行数 (假设每行约 50 字节)
        const estimated_lines = file_size / 50 + 1;
        var dataset = try DataSet.init(self.allocator, estimated_lines);
        dataset.mapped_data = mapped;

        // 解析 CSV
        try self.parseCsvContent(mapped, &dataset);

        return dataset;
    }

    /// 使用标准文件 I/O 加载 CSV
    fn loadCsvStandard(self: *Self, path: []const u8) !DataSet {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        const content = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(content);

        const bytes_read = try file.readAll(content);
        if (bytes_read == 0) {
            return DataSet.init(self.allocator, 0);
        }

        // 估算行数
        const estimated_lines = bytes_read / 50 + 1;
        var dataset = try DataSet.init(self.allocator, estimated_lines);

        try self.parseCsvContent(content[0..bytes_read], &dataset);

        return dataset;
    }

    /// 解析 CSV 内容
    fn parseCsvContent(self: *Self, content: []const u8, dataset: *DataSet) !void {
        _ = self;
        var line_iter = std.mem.splitScalar(u8, content, '\n');

        // 跳过表头 (如果存在)
        if (line_iter.peek()) |first_line| {
            if (std.mem.startsWith(u8, first_line, "timestamp") or
                std.mem.startsWith(u8, first_line, "time") or
                std.mem.startsWith(u8, first_line, "date"))
            {
                _ = line_iter.next();
            }
        }

        var index: usize = 0;
        while (line_iter.next()) |line| {
            if (line.len == 0) continue;

            // 移除可能的 \r
            const clean_line = std.mem.trimRight(u8, line, "\r");
            if (clean_line.len == 0) continue;

            // 解析行
            if (try parseLine(clean_line)) |candle| {
                if (index >= dataset.timestamps.len) {
                    // 需要扩展数组 (这种情况应该很少发生)
                    break;
                }

                dataset.timestamps[index] = candle.timestamp;
                dataset.opens[index] = candle.open;
                dataset.highs[index] = candle.high;
                dataset.lows[index] = candle.low;
                dataset.closes[index] = candle.close;
                dataset.volumes[index] = candle.volume;
                index += 1;
            }
        }

        dataset.len = index;
    }

    /// 解析单行 CSV
    fn parseLine(line: []const u8) !?VecCandle {
        var field_iter = std.mem.splitScalar(u8, line, ',');

        // 解析时间戳
        const timestamp_str = field_iter.next() orelse return null;
        const timestamp = std.fmt.parseInt(i64, timestamp_str, 10) catch {
            // 尝试解析日期格式
            return null; // TODO: 支持日期格式
        };

        // 解析 OHLCV
        const open_str = field_iter.next() orelse return null;
        const high_str = field_iter.next() orelse return null;
        const low_str = field_iter.next() orelse return null;
        const close_str = field_iter.next() orelse return null;
        const volume_str = field_iter.next() orelse return null;

        return VecCandle{
            .timestamp = timestamp,
            .open = try std.fmt.parseFloat(f64, open_str),
            .high = try std.fmt.parseFloat(f64, high_str),
            .low = try std.fmt.parseFloat(f64, low_str),
            .close = try std.fmt.parseFloat(f64, close_str),
            .volume = try std.fmt.parseFloat(f64, volume_str),
        };
    }

    /// 从内存数据创建数据集
    pub fn fromSlice(self: *const Self, candles: []const VecCandle) !DataSet {
        var dataset = try DataSet.init(self.allocator, candles.len);

        for (candles, 0..) |candle, i| {
            dataset.timestamps[i] = candle.timestamp;
            dataset.opens[i] = candle.open;
            dataset.highs[i] = candle.high;
            dataset.lows[i] = candle.low;
            dataset.closes[i] = candle.close;
            dataset.volumes[i] = candle.volume;
        }

        dataset.len = candles.len;
        return dataset;
    }

    /// 从数组创建数据集 (便于测试)
    pub fn fromArrays(
        self: *const Self,
        timestamps: []const i64,
        opens: []const f64,
        highs: []const f64,
        lows: []const f64,
        closes: []const f64,
        volumes: []const f64,
    ) !DataSet {
        const len = timestamps.len;
        std.debug.assert(opens.len == len);
        std.debug.assert(highs.len == len);
        std.debug.assert(lows.len == len);
        std.debug.assert(closes.len == len);
        std.debug.assert(volumes.len == len);

        var dataset = try DataSet.init(self.allocator, len);

        @memcpy(dataset.timestamps[0..len], timestamps);
        @memcpy(dataset.opens[0..len], opens);
        @memcpy(dataset.highs[0..len], highs);
        @memcpy(dataset.lows[0..len], lows);
        @memcpy(dataset.closes[0..len], closes);
        @memcpy(dataset.volumes[0..len], volumes);

        dataset.len = len;
        return dataset;
    }
};

/// 生成测试数据
pub fn generateTestData(allocator: Allocator, count: usize, seed: u64) !DataSet {
    const loader = MmapDataLoader.init(allocator, false);
    var dataset = try DataSet.init(allocator, count);

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    var price: f64 = 100.0;
    const base_timestamp: i64 = 1700000000;

    for (0..count) |i| {
        // 随机价格变动
        const change = (random.float(f64) - 0.5) * 2.0;
        price = @max(price + change, 1.0);

        const open = price;
        const high = price + random.float(f64) * 2.0;
        const low = price - random.float(f64) * 2.0;
        const close = low + random.float(f64) * (high - low);
        const volume = random.float(f64) * 10000.0 + 1000.0;

        dataset.timestamps[i] = base_timestamp + @as(i64, @intCast(i)) * 60;
        dataset.opens[i] = open;
        dataset.highs[i] = high;
        dataset.lows[i] = @max(low, 0.01);
        dataset.closes[i] = close;
        dataset.volumes[i] = volume;

        price = close;
    }

    dataset.len = count;
    _ = loader;
    return dataset;
}

// ============================================================================
// 单元测试
// ============================================================================

test "DataSet basic operations" {
    const allocator = std.testing.allocator;

    var dataset = try DataSet.init(allocator, 10);
    defer dataset.deinit();

    dataset.timestamps[0] = 1000;
    dataset.opens[0] = 100.0;
    dataset.highs[0] = 105.0;
    dataset.lows[0] = 98.0;
    dataset.closes[0] = 102.0;
    dataset.volumes[0] = 1000.0;
    dataset.len = 1;

    const candle = dataset.getCandle(0).?;
    try std.testing.expectEqual(@as(i64, 1000), candle.timestamp);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), candle.open, 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 102.0), candle.close, 1e-10);
}

test "MmapDataLoader fromArrays" {
    const allocator = std.testing.allocator;

    const loader = MmapDataLoader.init(allocator, false);

    const timestamps = [_]i64{ 1000, 1060, 1120 };
    const opens = [_]f64{ 100.0, 101.0, 102.0 };
    const highs = [_]f64{ 105.0, 106.0, 107.0 };
    const lows = [_]f64{ 98.0, 99.0, 100.0 };
    const closes = [_]f64{ 102.0, 103.0, 104.0 };
    const volumes = [_]f64{ 1000.0, 1100.0, 1200.0 };

    var dataset = try loader.fromArrays(&timestamps, &opens, &highs, &lows, &closes, &volumes);
    defer dataset.deinit();

    try std.testing.expectEqual(@as(usize, 3), dataset.len);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), dataset.opens[0], 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 104.0), dataset.closes[2], 1e-10);
}

test "generateTestData" {
    const allocator = std.testing.allocator;

    var dataset = try generateTestData(allocator, 1000, 12345);
    defer dataset.deinit();

    try std.testing.expectEqual(@as(usize, 1000), dataset.len);

    // 验证数据合理性
    for (0..dataset.len) |i| {
        try std.testing.expect(dataset.highs[i] >= dataset.lows[i]);
        try std.testing.expect(dataset.closes[i] >= dataset.lows[i]);
        try std.testing.expect(dataset.closes[i] <= dataset.highs[i]);
        try std.testing.expect(dataset.volumes[i] > 0);
    }
}

test "CSV line parsing" {
    const line = "1700000000,100.5,105.2,98.3,102.1,50000.0";
    const candle = try MmapDataLoader.parseLine(line);

    try std.testing.expect(candle != null);
    try std.testing.expectEqual(@as(i64, 1700000000), candle.?.timestamp);
    try std.testing.expectApproxEqAbs(@as(f64, 100.5), candle.?.open, 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 102.1), candle.?.close, 1e-10);
}
