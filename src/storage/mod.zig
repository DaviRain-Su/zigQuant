//! Storage Module
//!
//! 提供数据持久化功能，存储历史 K 线数据和回测结果。
//!
//! ## Story 036: 数据持久化
//!
//! 该模块实现 K 线数据缓存和回测结果存储：
//! - DataStore: 核心存储管理器
//! - CandleCache: 带 LRU 淘汰的内存缓存
//!
//! ## 使用示例
//!
//! ```zig
//! const storage = @import("storage");
//!
//! // 打开数据存储 (文件模式)
//! var store = try storage.DataStore.open(allocator, "./data");
//! defer store.close();
//!
//! // 存储 K 线数据
//! const candles = [_]storage.StoredCandle{
//!     .{ .timestamp = 1000, .open = 100.0, .high = 105.0, .low = 99.0, .close = 103.0, .volume = 1000.0 },
//! };
//! try store.storeCandles("ETH", "1h", &candles);
//!
//! // 加载 K 线数据
//! const loaded = try store.loadCandles("ETH", "1h", 0, 2000);
//! defer allocator.free(loaded);
//!
//! // 使用缓存
//! var cache = storage.CandleCache.init(allocator, &store, 100000);
//! defer cache.deinit();
//!
//! const cached = try cache.get("ETH", "1h", 0, 2000);
//! defer allocator.free(cached);
//! ```
//!
//! ## 内存模式
//!
//! 使用 `:memory:` 作为路径可以启用纯内存模式，适合测试：
//!
//! ```zig
//! var store = try storage.DataStore.open(allocator, ":memory:");
//! defer store.close();
//! ```

// Sub-modules
pub const types = @import("types.zig");
pub const data_store = @import("data_store.zig");
pub const candle_cache = @import("candle_cache.zig");

// Re-export types
pub const StoredCandle = types.StoredCandle;
pub const BacktestRecord = types.BacktestRecord;
pub const TradeRecord = types.TradeRecord;
pub const DbStats = types.DbStats;
pub const CacheEntry = types.CacheEntry;
pub const StorageError = types.StorageError;
pub const Timeframe = types.Timeframe;

// Re-export DataStore
pub const DataStore = data_store.DataStore;

// Re-export CandleCache
pub const CandleCache = candle_cache.CandleCache;
pub const CacheStats = candle_cache.CacheStats;

// ============================================================================
// Tests
// ============================================================================

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
