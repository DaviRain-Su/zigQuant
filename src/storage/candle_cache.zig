//! K 线缓存
//!
//! 结合内存缓存和持久化存储的 K 线数据管理器。
//! 提供 LRU 淘汰策略和自动同步机制。

const std = @import("std");
const Allocator = std.mem.Allocator;
const DataStore = @import("data_store.zig").DataStore;
const types = @import("types.zig");
const StoredCandle = types.StoredCandle;
const CacheEntry = types.CacheEntry;

/// K 线缓存管理器
pub const CandleCache = struct {
    allocator: Allocator,
    /// 底层存储
    store: *DataStore,
    /// 内存缓存
    cache: std.StringHashMap(CacheEntry),
    /// 最大内存 K 线数量
    max_memory_candles: usize,
    /// 当前内存 K 线数量
    current_candle_count: usize,
    /// 缓存命中次数
    cache_hits: u64,
    /// 缓存未命中次数
    cache_misses: u64,

    const Self = @This();

    /// 初始化缓存
    pub fn init(allocator: Allocator, store: *DataStore, max_candles: usize) Self {
        return .{
            .allocator = allocator,
            .store = store,
            .cache = std.StringHashMap(CacheEntry).init(allocator),
            .max_memory_candles = max_candles,
            .current_candle_count = 0,
            .cache_hits = 0,
            .cache_misses = 0,
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.candles);
        }
        self.cache.deinit();
    }

    /// 获取 K 线数据
    /// 优先从内存缓存获取，缓存未命中则从存储加载
    pub fn get(
        self: *Self,
        symbol: []const u8,
        timeframe: []const u8,
        start: i64,
        end: i64,
    ) ![]StoredCandle {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ symbol, timeframe });

        // 检查内存缓存
        if (self.cache.getPtr(key)) |entry| {
            self.allocator.free(key);
            entry.last_access = std.time.milliTimestamp();
            self.cache_hits += 1;

            // 过滤时间范围
            var result = std.ArrayList(StoredCandle).initCapacity(self.allocator, 0) catch unreachable;
            for (entry.candles) |c| {
                if (c.timestamp >= start and c.timestamp <= end) {
                    try result.append(self.allocator, c);
                }
            }
            return try result.toOwnedSlice(self.allocator);
        }

        self.allocator.free(key);
        self.cache_misses += 1;

        // 从存储加载
        const candles = try self.store.loadCandles(symbol, timeframe, start, end);

        // 如果数据量不太大，加入缓存
        if (candles.len > 0 and candles.len <= self.max_memory_candles / 2) {
            try self.addToCache(symbol, timeframe, candles);
        }

        return candles;
    }

    /// 设置 K 线数据
    /// 同时更新内存缓存和持久化存储
    pub fn set(
        self: *Self,
        symbol: []const u8,
        timeframe: []const u8,
        candles: []const StoredCandle,
    ) !void {
        // 存储到持久化
        try self.store.storeCandles(symbol, timeframe, candles);

        // 更新内存缓存
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ symbol, timeframe });

        if (self.cache.getPtr(key)) |entry| {
            self.allocator.free(key);
            // 合并数据
            try self.mergeCandles(entry, candles);
        } else {
            // 检查是否需要淘汰
            if (self.current_candle_count + candles.len > self.max_memory_candles) {
                try self.evictLRU(candles.len);
            }

            // 添加新条目
            const owned_candles = try self.allocator.dupe(StoredCandle, candles);
            try self.cache.put(key, .{
                .candles = owned_candles,
                .last_access = std.time.milliTimestamp(),
                .dirty = false,
            });
            self.current_candle_count += candles.len;
        }
    }

    /// 追加 K 线数据 (增量更新)
    pub fn append(
        self: *Self,
        symbol: []const u8,
        timeframe: []const u8,
        candles: []const StoredCandle,
    ) !void {
        // 存储到持久化
        try self.store.storeCandles(symbol, timeframe, candles);

        // 更新内存缓存
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ symbol, timeframe });

        if (self.cache.getPtr(key)) |entry| {
            self.allocator.free(key);
            try self.mergeCandles(entry, candles);
        } else {
            self.allocator.free(key);
            // 不在缓存中则不加载，下次 get 时自动加载
        }
    }

    /// 同步所有脏数据到存储
    pub fn sync(self: *Self) !void {
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.dirty) {
                // 解析 key
                var parts = std.mem.splitSequence(u8, entry.key_ptr.*, ":");
                const symbol = parts.next() orelse continue;
                const timeframe = parts.next() orelse continue;

                try self.store.storeCandles(symbol, timeframe, entry.value_ptr.candles);
                entry.value_ptr.dirty = false;
            }
        }
    }

    /// 使缓存条目失效
    pub fn invalidate(self: *Self, symbol: []const u8, timeframe: []const u8) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ symbol, timeframe });
        defer self.allocator.free(key);

        if (self.cache.fetchRemove(key)) |entry| {
            self.current_candle_count -= entry.value.candles.len;
            self.allocator.free(entry.key);
            self.allocator.free(entry.value.candles);
        }
    }

    /// 清空所有缓存
    pub fn clear(self: *Self) void {
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.candles);
        }
        self.cache.clearRetainingCapacity();
        self.current_candle_count = 0;
    }

    /// 获取缓存统计
    pub fn getStats(self: *Self) CacheStats {
        const hit_rate = if (self.cache_hits + self.cache_misses > 0)
            @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(self.cache_hits + self.cache_misses))
        else
            0.0;

        return .{
            .cached_series = self.cache.count(),
            .cached_candles = self.current_candle_count,
            .max_candles = self.max_memory_candles,
            .cache_hits = self.cache_hits,
            .cache_misses = self.cache_misses,
            .hit_rate = hit_rate,
        };
    }

    /// 预热缓存
    pub fn warmup(
        self: *Self,
        symbol: []const u8,
        timeframe: []const u8,
        start: i64,
        end: i64,
    ) !void {
        const candles = try self.store.loadCandles(symbol, timeframe, start, end);
        defer self.allocator.free(candles);

        if (candles.len > 0 and candles.len <= self.max_memory_candles) {
            try self.addToCache(symbol, timeframe, candles);
        }
    }

    // ========================================================================
    // 私有方法
    // ========================================================================

    fn addToCache(self: *Self, symbol: []const u8, timeframe: []const u8, candles: []const StoredCandle) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ symbol, timeframe });

        // 检查是否需要淘汰
        if (self.current_candle_count + candles.len > self.max_memory_candles) {
            try self.evictLRU(candles.len);
        }

        const owned_candles = try self.allocator.dupe(StoredCandle, candles);
        try self.cache.put(key, .{
            .candles = owned_candles,
            .last_access = std.time.milliTimestamp(),
            .dirty = false,
        });
        self.current_candle_count += candles.len;
    }

    fn mergeCandles(self: *Self, entry: *CacheEntry, new_candles: []const StoredCandle) !void {
        var merged = std.ArrayList(StoredCandle).initCapacity(self.allocator, 0) catch unreachable;
        errdefer merged.deinit(self.allocator);

        // 添加现有数据
        for (entry.candles) |c| {
            try merged.append(self.allocator, c);
        }

        // 合并新数据
        for (new_candles) |new_c| {
            var found = false;
            for (merged.items) |*existing| {
                if (existing.timestamp == new_c.timestamp) {
                    existing.* = new_c;
                    found = true;
                    break;
                }
            }
            if (!found) {
                try merged.append(self.allocator, new_c);
            }
        }

        // 排序
        std.mem.sort(StoredCandle, merged.items, {}, struct {
            fn lessThan(_: void, a: StoredCandle, b: StoredCandle) bool {
                return a.timestamp < b.timestamp;
            }
        }.lessThan);

        // 更新条目
        const old_len = entry.candles.len;
        self.allocator.free(entry.candles);
        entry.candles = try merged.toOwnedSlice(self.allocator);
        entry.last_access = std.time.milliTimestamp();
        entry.dirty = true;

        self.current_candle_count = self.current_candle_count - old_len + entry.candles.len;
    }

    fn evictLRU(self: *Self, needed: usize) !void {
        while (self.current_candle_count + needed > self.max_memory_candles and self.cache.count() > 0) {
            // 找到最久未访问的条目
            var oldest_key: ?[]const u8 = null;
            var oldest_time: i64 = std.math.maxInt(i64);

            var iter = self.cache.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.last_access < oldest_time) {
                    oldest_time = entry.value_ptr.last_access;
                    oldest_key = entry.key_ptr.*;
                }
            }

            if (oldest_key) |key| {
                if (self.cache.fetchRemove(key)) |entry| {
                    // 如果是脏数据，先同步
                    if (entry.value.dirty) {
                        var parts = std.mem.splitSequence(u8, key, ":");
                        const symbol = parts.next() orelse continue;
                        const timeframe = parts.next() orelse continue;
                        try self.store.storeCandles(symbol, timeframe, entry.value.candles);
                    }

                    self.current_candle_count -= entry.value.candles.len;
                    self.allocator.free(entry.key);
                    self.allocator.free(entry.value.candles);
                }
            } else {
                break;
            }
        }
    }
};

/// 缓存统计
pub const CacheStats = struct {
    /// 缓存的序列数
    cached_series: usize,
    /// 缓存的 K 线数
    cached_candles: usize,
    /// 最大 K 线数
    max_candles: usize,
    /// 缓存命中次数
    cache_hits: u64,
    /// 缓存未命中次数
    cache_misses: u64,
    /// 命中率
    hit_rate: f64,
};

// ============================================================================
// Tests
// ============================================================================

test "CandleCache: basic get/set" {
    const allocator = std.testing.allocator;

    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    var cache = CandleCache.init(allocator, &store, 1000);
    defer cache.deinit();

    const candles = [_]StoredCandle{
        .{ .timestamp = 1000, .open = 100.0, .high = 105.0, .low = 99.0, .close = 103.0, .volume = 1000.0 },
        .{ .timestamp = 2000, .open = 103.0, .high = 108.0, .low = 101.0, .close = 106.0, .volume = 1500.0 },
    };

    try cache.set("ETH", "1h", &candles);

    // 第一次获取 (可能从缓存)
    const loaded1 = try cache.get("ETH", "1h", 0, 3000);
    defer allocator.free(loaded1);
    try std.testing.expectEqual(@as(usize, 2), loaded1.len);

    // 第二次获取 (应该从缓存)
    const loaded2 = try cache.get("ETH", "1h", 0, 3000);
    defer allocator.free(loaded2);
    try std.testing.expectEqual(@as(usize, 2), loaded2.len);
}

test "CandleCache: cache stats" {
    const allocator = std.testing.allocator;

    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    var cache = CandleCache.init(allocator, &store, 1000);
    defer cache.deinit();

    var stats = cache.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats.cached_series);
    try std.testing.expectEqual(@as(usize, 0), stats.cached_candles);

    const candles = [_]StoredCandle{
        .{ .timestamp = 1000, .open = 100.0, .high = 105.0, .low = 99.0, .close = 103.0, .volume = 1000.0 },
    };

    try cache.set("ETH", "1h", &candles);

    stats = cache.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.cached_series);
    try std.testing.expectEqual(@as(usize, 1), stats.cached_candles);
}

test "CandleCache: LRU eviction" {
    const allocator = std.testing.allocator;

    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    // 设置很小的最大容量
    var cache = CandleCache.init(allocator, &store, 5);
    defer cache.deinit();

    // 添加第一批数据
    const candles1 = [_]StoredCandle{
        .{ .timestamp = 1000, .open = 100.0, .high = 105.0, .low = 99.0, .close = 103.0, .volume = 1000.0 },
        .{ .timestamp = 2000, .open = 103.0, .high = 108.0, .low = 101.0, .close = 106.0, .volume = 1500.0 },
    };
    try cache.set("ETH", "1h", &candles1);

    // 添加第二批数据 (应该触发淘汰)
    const candles2 = [_]StoredCandle{
        .{ .timestamp = 3000, .open = 200.0, .high = 205.0, .low = 199.0, .close = 203.0, .volume = 2000.0 },
        .{ .timestamp = 4000, .open = 203.0, .high = 208.0, .low = 201.0, .close = 206.0, .volume = 2500.0 },
        .{ .timestamp = 5000, .open = 206.0, .high = 210.0, .low = 204.0, .close = 209.0, .volume = 3000.0 },
    };
    try cache.set("BTC", "1h", &candles2);

    const stats = cache.getStats();
    try std.testing.expect(stats.cached_candles <= 5);
}

test "CandleCache: invalidate" {
    const allocator = std.testing.allocator;

    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    var cache = CandleCache.init(allocator, &store, 1000);
    defer cache.deinit();

    const candles = [_]StoredCandle{
        .{ .timestamp = 1000, .open = 100.0, .high = 105.0, .low = 99.0, .close = 103.0, .volume = 1000.0 },
    };
    try cache.set("ETH", "1h", &candles);

    var stats = cache.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.cached_series);

    try cache.invalidate("ETH", "1h");

    stats = cache.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats.cached_series);

    // 数据仍在存储中
    const loaded = try cache.get("ETH", "1h", 0, 3000);
    defer allocator.free(loaded);
    try std.testing.expectEqual(@as(usize, 1), loaded.len);
}

test "CandleCache: clear" {
    const allocator = std.testing.allocator;

    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    var cache = CandleCache.init(allocator, &store, 1000);
    defer cache.deinit();

    const candles1 = [_]StoredCandle{
        .{ .timestamp = 1000, .open = 100.0, .high = 105.0, .low = 99.0, .close = 103.0, .volume = 1000.0 },
    };
    const candles2 = [_]StoredCandle{
        .{ .timestamp = 2000, .open = 200.0, .high = 205.0, .low = 199.0, .close = 203.0, .volume = 2000.0 },
    };

    try cache.set("ETH", "1h", &candles1);
    try cache.set("BTC", "1h", &candles2);

    var stats = cache.getStats();
    try std.testing.expectEqual(@as(usize, 2), stats.cached_series);

    cache.clear();

    stats = cache.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats.cached_series);
    try std.testing.expectEqual(@as(usize, 0), stats.cached_candles);
}

test "CandleCache: append" {
    const allocator = std.testing.allocator;

    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    var cache = CandleCache.init(allocator, &store, 1000);
    defer cache.deinit();

    // 初始数据
    const candles1 = [_]StoredCandle{
        .{ .timestamp = 1000, .open = 100.0, .high = 105.0, .low = 99.0, .close = 103.0, .volume = 1000.0 },
    };
    try cache.set("ETH", "1h", &candles1);

    // 追加新数据
    const candles2 = [_]StoredCandle{
        .{ .timestamp = 2000, .open = 103.0, .high = 108.0, .low = 101.0, .close = 106.0, .volume = 1500.0 },
    };
    try cache.append("ETH", "1h", &candles2);

    // 验证合并
    const loaded = try cache.get("ETH", "1h", 0, 3000);
    defer allocator.free(loaded);
    try std.testing.expectEqual(@as(usize, 2), loaded.len);
}
