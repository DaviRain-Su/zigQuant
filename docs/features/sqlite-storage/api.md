# SQLite Storage API 参考

> 数据持久化模块的完整 API 文档

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 目录

1. [核心类型](#核心类型)
2. [DataStore](#datastore)
3. [CandleCache](#candlecache)
4. [BacktestResultStore](#backtestresultstore)
5. [使用示例](#使用示例)

---

## 核心类型

### StorageConfig

存储配置结构。

```zig
pub const StorageConfig = struct {
    /// 数据库文件路径
    db_path: []const u8 = "data/zigquant.db",

    /// 是否启用 WAL 模式
    enable_wal: bool = true,

    /// 缓存大小 (页数)
    cache_size: u32 = 2000,

    /// 同步模式
    sync_mode: SyncMode = .normal,

    /// 是否自动创建表
    auto_create_tables: bool = true,

    pub const SyncMode = enum {
        off,      // 最快，不安全
        normal,   // 平衡
        full,     // 最安全，较慢
    };
};
```

### CandleRecord

K 线数据记录。

```zig
pub const CandleRecord = struct {
    id: ?i64 = null,
    symbol: []const u8,
    timeframe: Timeframe,
    timestamp: i64,
    open: Decimal,
    high: Decimal,
    low: Decimal,
    close: Decimal,
    volume: Decimal,
};
```

### BacktestResultRecord

回测结果记录。

```zig
pub const BacktestResultRecord = struct {
    id: ?i64 = null,
    strategy: []const u8,
    symbol: []const u8,
    timeframe: Timeframe,
    start_time: i64,
    end_time: i64,
    total_return: f64,
    sharpe_ratio: f64,
    max_drawdown: f64,
    total_trades: u32,
    win_rate: f64,
    params_json: ?[]const u8 = null,
    created_at: i64,
};
```

### TradeRecord

交易记录。

```zig
pub const TradeRecord = struct {
    id: ?i64 = null,
    backtest_id: i64,
    timestamp: i64,
    side: OrderSide,
    price: Decimal,
    quantity: Decimal,
    pnl: ?Decimal = null,
};
```

---

## DataStore

数据存储主结构。

### open

```zig
pub fn open(allocator: Allocator, path: []const u8) !DataStore
```

打开或创建数据库。

**参数**:
- `allocator`: 内存分配器
- `path`: 数据库文件路径

**返回**: DataStore 实例

**错误**:
- `error.OpenFailed`: 无法打开数据库
- `error.SchemaError`: Schema 初始化失败

**示例**:
```zig
var store = try DataStore.open(allocator, "data/zigquant.db");
defer store.close();
```

### openWithConfig

```zig
pub fn openWithConfig(allocator: Allocator, config: StorageConfig) !DataStore
```

使用配置打开数据库。

**参数**:
- `allocator`: 内存分配器
- `config`: 存储配置

### close

```zig
pub fn close(self: *DataStore) void
```

关闭数据库连接。

### storeCandles

```zig
pub fn storeCandles(
    self: *DataStore,
    symbol: []const u8,
    timeframe: Timeframe,
    candles: []const Candle,
) !void
```

批量存储 K 线数据。

**参数**:
- `symbol`: 交易对符号
- `timeframe`: 时间周期
- `candles`: K 线数组

**说明**: 使用 UPSERT 语义，相同 (symbol, timeframe, timestamp) 会更新。

**示例**:
```zig
const candles = try fetchCandles("ETH-USD", .@"1h", start, end);
try store.storeCandles("ETH-USD", .@"1h", candles);
```

### loadCandles

```zig
pub fn loadCandles(
    self: *DataStore,
    symbol: []const u8,
    timeframe: Timeframe,
    start_time: i64,
    end_time: i64,
) ![]Candle
```

加载 K 线数据。

**参数**:
- `symbol`: 交易对符号
- `timeframe`: 时间周期
- `start_time`: 起始时间戳 (纳秒)
- `end_time`: 结束时间戳 (纳秒)

**返回**: K 线数组 (调用者负责释放)

### getLatestTimestamp

```zig
pub fn getLatestTimestamp(
    self: *DataStore,
    symbol: []const u8,
    timeframe: Timeframe,
) !?i64
```

获取最新的 K 线时间戳。

**返回**: 最新时间戳，或 null 如果没有数据

**用途**: 用于增量更新，只获取新数据。

**示例**:
```zig
const latest = try store.getLatestTimestamp("ETH-USD", .@"1h");
if (latest) |ts| {
    // 从 ts 之后获取新数据
    const new_candles = try provider.getCandles("ETH-USD", .@"1h", ts, now);
    try store.storeCandles("ETH-USD", .@"1h", new_candles);
}
```

### countCandles

```zig
pub fn countCandles(
    self: *DataStore,
    symbol: []const u8,
    timeframe: Timeframe,
) !u64
```

统计 K 线数量。

### deleteCandles

```zig
pub fn deleteCandles(
    self: *DataStore,
    symbol: []const u8,
    timeframe: Timeframe,
    before: ?i64,
) !u64
```

删除 K 线数据。

**参数**:
- `before`: 如果指定，只删除此时间之前的数据

**返回**: 删除的记录数

### storeBacktestResult

```zig
pub fn storeBacktestResult(
    self: *DataStore,
    result: BacktestResult,
) !u64
```

存储回测结果。

**返回**: 新记录的 ID

### loadBacktestResults

```zig
pub fn loadBacktestResults(
    self: *DataStore,
    strategy: ?[]const u8,
    limit: ?u32,
) ![]BacktestResultRecord
```

加载回测结果。

**参数**:
- `strategy`: 策略名称过滤 (可选)
- `limit`: 返回数量限制 (可选)

### storeTrades

```zig
pub fn storeTrades(
    self: *DataStore,
    backtest_id: i64,
    trades: []const Trade,
) !void
```

存储交易记录。

### loadTrades

```zig
pub fn loadTrades(
    self: *DataStore,
    backtest_id: i64,
) ![]TradeRecord
```

加载交易记录。

---

## CandleCache

带内存缓存的 K 线存储。

### init

```zig
pub fn init(
    allocator: Allocator,
    store: *DataStore,
    max_memory_mb: u32,
) CandleCache
```

创建缓存实例。

**参数**:
- `allocator`: 内存分配器
- `store`: 底层 DataStore
- `max_memory_mb`: 最大内存使用 (MB)

### get

```zig
pub fn get(
    self: *CandleCache,
    symbol: []const u8,
    timeframe: Timeframe,
    start: i64,
    end: i64,
) ![]Candle
```

获取 K 线 (优先内存缓存)。

**流程**:
1. 检查内存缓存
2. 缓存命中 → 返回
3. 缓存未命中 → 从磁盘加载 → 更新缓存 → 返回

### set

```zig
pub fn set(
    self: *CandleCache,
    symbol: []const u8,
    timeframe: Timeframe,
    candles: []const Candle,
) !void
```

设置 K 线 (同时写入内存和磁盘)。

### invalidate

```zig
pub fn invalidate(
    self: *CandleCache,
    symbol: ?[]const u8,
    timeframe: ?Timeframe,
) void
```

使缓存失效。

### sync

```zig
pub fn sync(self: *CandleCache) !void
```

同步内存缓存到磁盘。

### getStats

```zig
pub fn getStats(self: *CandleCache) CacheStats
```

获取缓存统计。

```zig
pub const CacheStats = struct {
    hits: u64,
    misses: u64,
    memory_used_bytes: u64,
    entry_count: u64,

    pub fn hitRate(self: CacheStats) f64 {
        const total = self.hits + self.misses;
        return if (total > 0) @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total)) else 0;
    }
};
```

---

## BacktestResultStore

回测结果专用存储。

### init

```zig
pub fn init(store: *DataStore) BacktestResultStore
```

### save

```zig
pub fn save(self: *BacktestResultStore, result: BacktestResult) !u64
```

保存回测结果。

### load

```zig
pub fn load(self: *BacktestResultStore, id: i64) !?BacktestResultRecord
```

加载单个回测结果。

### list

```zig
pub fn list(
    self: *BacktestResultStore,
    filter: ResultFilter,
) ![]BacktestResultRecord
```

列出回测结果。

```zig
pub const ResultFilter = struct {
    strategy: ?[]const u8 = null,
    symbol: ?[]const u8 = null,
    min_sharpe: ?f64 = null,
    after: ?i64 = null,
    limit: u32 = 100,
    order_by: OrderBy = .created_at_desc,

    pub const OrderBy = enum {
        created_at_desc,
        sharpe_ratio_desc,
        total_return_desc,
    };
};
```

### compare

```zig
pub fn compare(
    self: *BacktestResultStore,
    ids: []const i64,
) !ComparisonResult
```

比较多个回测结果。

---

## 使用示例

### 基本使用

```zig
const std = @import("std");
const DataStore = @import("storage/data_store.zig").DataStore;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 打开数据库
    var store = try DataStore.open(allocator, "data/trading.db");
    defer store.close();

    // 存储 K 线
    const candles = [_]Candle{
        .{ .timestamp = 1000000, .open = d(100), .high = d(105), .low = d(99), .close = d(102), .volume = d(1000) },
        .{ .timestamp = 1003600, .open = d(102), .high = d(108), .low = d(101), .close = d(107), .volume = d(1500) },
    };
    try store.storeCandles("ETH-USD", .@"1h", &candles);

    // 加载 K 线
    const loaded = try store.loadCandles("ETH-USD", .@"1h", 0, 2000000);
    defer allocator.free(loaded);

    std.debug.print("Loaded {} candles\n", .{loaded.len});
}

fn d(v: f64) Decimal {
    return Decimal.fromFloat(v);
}
```

### 增量更新

```zig
pub fn updateCandleData(store: *DataStore, provider: *MarketDataProvider) !void {
    const symbol = "ETH-USD";
    const timeframe = Timeframe.@"1h";

    // 获取最新时间戳
    const latest = try store.getLatestTimestamp(symbol, timeframe);
    const start = latest orelse 0;
    const end = std.time.nanoTimestamp();

    // 获取新数据
    const new_candles = try provider.getCandles(symbol, timeframe, start, end);
    defer provider.allocator.free(new_candles);

    if (new_candles.len > 0) {
        try store.storeCandles(symbol, timeframe, new_candles);
        std.debug.print("Updated {} new candles\n", .{new_candles.len});
    }
}
```

### 回测结果管理

```zig
pub fn saveAndCompareBacktest(store: *DataStore, result: BacktestResult) !void {
    var result_store = BacktestResultStore.init(store);

    // 保存新结果
    const id = try result_store.save(result);
    std.debug.print("Saved backtest result: {}\n", .{id});

    // 比较历史最佳
    const best = try result_store.list(.{
        .strategy = result.strategy_name,
        .order_by = .sharpe_ratio_desc,
        .limit = 5,
    });
    defer store.allocator.free(best);

    std.debug.print("Top 5 results for {}:\n", .{result.strategy_name});
    for (best, 0..) |r, i| {
        std.debug.print("  {}. Sharpe: {d:.2}, Return: {d:.2}%\n", .{
            i + 1,
            r.sharpe_ratio,
            r.total_return * 100,
        });
    }
}
```

---

## 错误处理

```zig
pub const StorageError = error{
    /// 无法打开数据库
    OpenFailed,

    /// 查询执行失败
    QueryFailed,

    /// 数据库锁定
    DatabaseLocked,

    /// Schema 版本不匹配
    SchemaMismatch,

    /// 数据损坏
    DataCorruption,

    /// 磁盘空间不足
    DiskFull,

    /// 内存不足
    OutOfMemory,
};
```

---

## 性能说明

| 操作 | 预期延迟 | 说明 |
|------|----------|------|
| storeCandles (1条) | < 1ms | 单条插入 |
| storeCandles (1000条) | < 100ms | 批量插入 (事务) |
| loadCandles | < 10ms | 依赖数据量 |
| getLatestTimestamp | < 1ms | 使用索引 |
| 缓存命中 | < 100μs | 内存访问 |

---

*Last updated: 2025-12-27*
