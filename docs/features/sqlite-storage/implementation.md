# SQLite Storage 实现细节

> 数据持久化模块的内部实现文档

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 目录

1. [架构概述](#架构概述)
2. [数据库设计](#数据库设计)
3. [zig-sqlite 集成](#zig-sqlite-集成)
4. [数据操作](#数据操作)
5. [缓存实现](#缓存实现)
6. [性能优化](#性能优化)

---

## 架构概述

### 模块结构

```
src/storage/
├── data_store.zig        # 主存储接口
├── schema.zig            # 数据库 Schema
├── candle_store.zig      # K 线存储
├── backtest_store.zig    # 回测结果存储
├── cache.zig             # 内存缓存
├── migrations.zig        # Schema 迁移
└── tests/
    └── storage_test.zig  # 测试
```

### 组件关系

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Layer                        │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ Backtest    │    │ DataFetcher │    │ Analytics   │     │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘     │
└─────────┼──────────────────┼──────────────────┼─────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────┐
│                      CandleCache                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              In-Memory LRU Cache                     │    │
│  └──────────────────────┬──────────────────────────────┘    │
└─────────────────────────┼───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                       DataStore                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ CandleStore │    │BacktestStore│    │ TradeStore  │     │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘     │
└─────────┼──────────────────┼──────────────────┼─────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────┐
│                    zig-sqlite                                │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                  SQLite Database                     │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## 数据库设计

### Schema 定义

```sql
-- 版本控制
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY
);

-- K 线数据表
CREATE TABLE IF NOT EXISTS candles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    symbol TEXT NOT NULL,
    timeframe TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    open TEXT NOT NULL,          -- Decimal 存为字符串
    high TEXT NOT NULL,
    low TEXT NOT NULL,
    close TEXT NOT NULL,
    volume TEXT NOT NULL,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    UNIQUE(symbol, timeframe, timestamp)
);

-- K 线索引
CREATE INDEX IF NOT EXISTS idx_candles_symbol_tf_ts
    ON candles(symbol, timeframe, timestamp);

CREATE INDEX IF NOT EXISTS idx_candles_ts
    ON candles(timestamp);

-- 回测结果表
CREATE TABLE IF NOT EXISTS backtest_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    strategy TEXT NOT NULL,
    symbol TEXT NOT NULL,
    timeframe TEXT NOT NULL,
    start_time INTEGER NOT NULL,
    end_time INTEGER NOT NULL,
    total_return REAL NOT NULL,
    sharpe_ratio REAL NOT NULL,
    max_drawdown REAL NOT NULL,
    total_trades INTEGER NOT NULL,
    win_rate REAL NOT NULL,
    profit_factor REAL,
    avg_trade_pnl REAL,
    params_json TEXT,
    notes TEXT,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- 回测结果索引
CREATE INDEX IF NOT EXISTS idx_backtest_strategy
    ON backtest_results(strategy);

CREATE INDEX IF NOT EXISTS idx_backtest_created
    ON backtest_results(created_at DESC);

-- 交易记录表
CREATE TABLE IF NOT EXISTS trades (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    backtest_id INTEGER NOT NULL,
    timestamp INTEGER NOT NULL,
    side TEXT NOT NULL,           -- 'buy' | 'sell'
    price TEXT NOT NULL,
    quantity TEXT NOT NULL,
    fee TEXT,
    pnl TEXT,
    cumulative_pnl TEXT,
    FOREIGN KEY (backtest_id) REFERENCES backtest_results(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_trades_backtest
    ON trades(backtest_id);
```

### Decimal 存储策略

Decimal 值存储为字符串以保持精度:

```zig
/// Decimal 转 SQLite 值
fn decimalToSql(d: Decimal) []const u8 {
    return d.toString();
}

/// SQLite 值转 Decimal
fn sqlToDecimal(s: []const u8) !Decimal {
    return Decimal.parse(s);
}
```

---

## zig-sqlite 集成

### 依赖配置

```zig
// build.zig.zon
.dependencies = .{
    .sqlite = .{
        .url = "https://github.com/vrischmann/zig-sqlite/archive/...",
        .hash = "...",
    },
},
```

### 连接管理

```zig
const sqlite = @import("sqlite");

pub const DataStore = struct {
    allocator: Allocator,
    db: sqlite.Db,

    pub fn open(allocator: Allocator, path: []const u8) !DataStore {
        var db = try sqlite.Db.open(.{
            .path = path,
            .open_flags = .{
                .read_write = true,
                .create = true,
            },
        });

        // 启用 WAL 模式
        try db.exec("PRAGMA journal_mode=WAL");

        // 启用外键约束
        try db.exec("PRAGMA foreign_keys=ON");

        // 设置缓存大小 (2000 pages ≈ 8MB)
        try db.exec("PRAGMA cache_size=2000");

        // 初始化 Schema
        try initSchema(db);

        return DataStore{
            .allocator = allocator,
            .db = db,
        };
    }

    pub fn close(self: *DataStore) void {
        self.db.close();
    }
};
```

### 预编译语句

```zig
pub const DataStore = struct {
    // 预编译语句缓存
    stmt_insert_candle: ?sqlite.Statement = null,
    stmt_select_candles: ?sqlite.Statement = null,

    fn getInsertCandleStmt(self: *DataStore) !*sqlite.Statement {
        if (self.stmt_insert_candle == null) {
            self.stmt_insert_candle = try self.db.prepare(
                \\INSERT OR REPLACE INTO candles
                \\(symbol, timeframe, timestamp, open, high, low, close, volume)
                \\VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            );
        }
        return &self.stmt_insert_candle.?;
    }

    fn getSelectCandlesStmt(self: *DataStore) !*sqlite.Statement {
        if (self.stmt_select_candles == null) {
            self.stmt_select_candles = try self.db.prepare(
                \\SELECT timestamp, open, high, low, close, volume
                \\FROM candles
                \\WHERE symbol = ? AND timeframe = ?
                \\  AND timestamp >= ? AND timestamp <= ?
                \\ORDER BY timestamp ASC
            );
        }
        return &self.stmt_select_candles.?;
    }
};
```

---

## 数据操作

### K 线批量插入

```zig
pub fn storeCandles(
    self: *DataStore,
    symbol: []const u8,
    timeframe: Timeframe,
    candles: []const Candle,
) !void {
    // 开始事务
    try self.db.exec("BEGIN TRANSACTION");
    errdefer self.db.exec("ROLLBACK") catch {};

    const stmt = try self.getInsertCandleStmt();
    const tf_str = timeframe.toString();

    for (candles) |candle| {
        stmt.reset();
        try stmt.bind(.{
            symbol,
            tf_str,
            candle.timestamp,
            candle.open.toString(),
            candle.high.toString(),
            candle.low.toString(),
            candle.close.toString(),
            candle.volume.toString(),
        });
        _ = try stmt.step();
    }

    try self.db.exec("COMMIT");
}
```

### K 线查询

```zig
pub fn loadCandles(
    self: *DataStore,
    symbol: []const u8,
    timeframe: Timeframe,
    start_time: i64,
    end_time: i64,
) ![]Candle {
    const stmt = try self.getSelectCandlesStmt();
    stmt.reset();

    try stmt.bind(.{
        symbol,
        timeframe.toString(),
        start_time,
        end_time,
    });

    var candles = std.ArrayList(Candle).init(self.allocator);
    errdefer candles.deinit();

    while (try stmt.step()) |row| {
        try candles.append(Candle{
            .timestamp = row.get(i64, 0),
            .open = try Decimal.parse(row.get([]const u8, 1)),
            .high = try Decimal.parse(row.get([]const u8, 2)),
            .low = try Decimal.parse(row.get([]const u8, 3)),
            .close = try Decimal.parse(row.get([]const u8, 4)),
            .volume = try Decimal.parse(row.get([]const u8, 5)),
        });
    }

    return candles.toOwnedSlice();
}
```

### 回测结果存储

```zig
pub fn storeBacktestResult(
    self: *DataStore,
    result: BacktestResult,
) !u64 {
    try self.db.exec(
        \\INSERT INTO backtest_results
        \\(strategy, symbol, timeframe, start_time, end_time,
        \\ total_return, sharpe_ratio, max_drawdown, total_trades,
        \\ win_rate, params_json, created_at)
        \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ,
        .{
            result.strategy,
            result.symbol,
            result.timeframe.toString(),
            result.start_time,
            result.end_time,
            result.total_return,
            result.sharpe_ratio,
            result.max_drawdown,
            result.total_trades,
            result.win_rate,
            result.params_json,
            std.time.timestamp(),
        },
    );

    return @intCast(self.db.lastInsertRowId());
}
```

---

## 缓存实现

### LRU 缓存结构

```zig
pub const CandleCache = struct {
    allocator: Allocator,
    store: *DataStore,
    cache: std.HashMap(CacheKey, CacheEntry, CacheKeyContext, 80),
    lru_list: std.DoublyLinkedList(CacheKey),
    max_entries: usize,
    max_memory: usize,
    current_memory: usize,

    // 统计
    hits: u64 = 0,
    misses: u64 = 0,

    const CacheKey = struct {
        symbol: []const u8,
        timeframe: Timeframe,
        start: i64,
        end: i64,
    };

    const CacheEntry = struct {
        candles: []Candle,
        memory_size: usize,
        lru_node: *std.DoublyLinkedList(CacheKey).Node,
    };
};
```

### 缓存查询

```zig
pub fn get(
    self: *CandleCache,
    symbol: []const u8,
    timeframe: Timeframe,
    start: i64,
    end: i64,
) ![]Candle {
    const key = CacheKey{
        .symbol = symbol,
        .timeframe = timeframe,
        .start = start,
        .end = end,
    };

    // 尝试缓存命中
    if (self.cache.get(key)) |entry| {
        self.hits += 1;
        // 移动到 LRU 队列头部
        self.lru_list.remove(entry.lru_node);
        self.lru_list.prepend(entry.lru_node);
        return entry.candles;
    }

    // 缓存未命中
    self.misses += 1;

    // 从磁盘加载
    const candles = try self.store.loadCandles(symbol, timeframe, start, end);

    // 添加到缓存
    try self.addToCache(key, candles);

    return candles;
}
```

### 缓存淘汰

```zig
fn evictIfNeeded(self: *CandleCache) void {
    while (self.current_memory > self.max_memory or
           self.cache.count() > self.max_entries)
    {
        // 移除最久未使用的条目
        if (self.lru_list.pop()) |node| {
            const key = node.data;
            if (self.cache.fetchRemove(key)) |entry| {
                self.current_memory -= entry.value.memory_size;
                self.allocator.free(entry.value.candles);
            }
            self.allocator.destroy(node);
        } else {
            break;
        }
    }
}
```

---

## 性能优化

### 批量操作

使用事务包装批量操作:

```zig
pub fn storeCandlesBatch(
    self: *DataStore,
    batches: []const CandleBatch,
) !void {
    try self.db.exec("BEGIN TRANSACTION");
    errdefer self.db.exec("ROLLBACK") catch {};

    for (batches) |batch| {
        try self.storeCandles(batch.symbol, batch.timeframe, batch.candles);
    }

    try self.db.exec("COMMIT");
}
```

### 索引优化

确保常用查询有索引覆盖:

```sql
-- 复合索引覆盖主要查询
CREATE INDEX idx_candles_covering
    ON candles(symbol, timeframe, timestamp)
    INCLUDE (open, high, low, close, volume);
```

### WAL 模式

WAL (Write-Ahead Logging) 模式提供更好的并发性能:

```zig
// 启用 WAL
try db.exec("PRAGMA journal_mode=WAL");

// 检查点配置
try db.exec("PRAGMA wal_autocheckpoint=1000");
```

### 内存映射

对于只读场景，使用内存映射:

```zig
var db = try sqlite.Db.open(.{
    .path = path,
    .open_flags = .{ .read_only = true },
    .vfs = "unix-mmap",  // 使用内存映射 VFS
});
```

---

## Schema 迁移

### 版本管理

```zig
const CURRENT_SCHEMA_VERSION: u32 = 1;

fn initSchema(db: *sqlite.Db) !void {
    const version = getSchemaVersion(db);

    if (version < CURRENT_SCHEMA_VERSION) {
        try migrate(db, version, CURRENT_SCHEMA_VERSION);
    }
}

fn migrate(db: *sqlite.Db, from: u32, to: u32) !void {
    var v = from;
    while (v < to) : (v += 1) {
        switch (v) {
            0 => try migrateV0ToV1(db),
            else => return error.UnknownMigration,
        }
    }
    try setSchemaVersion(db, to);
}
```

---

*Last updated: 2025-12-27*
