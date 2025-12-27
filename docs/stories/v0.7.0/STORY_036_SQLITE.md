# Story 036: zig-sqlite 数据持久化

**版本**: v0.7.0
**状态**: 待开发
**优先级**: P1
**预计时间**: 3-4 天
**依赖**: 无 (可并行开发)

---

## 概述

集成 zig-sqlite 实现数据持久化，存储历史 K 线数据和回测结果。这为量化策略提供本地数据缓存和回测结果管理能力。

---

## 背景

### 为什么需要本地数据存储?

```
┌─────────────────────────────────────────────────────────────────┐
│                      数据存储需求                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. K 线数据缓存                                                │
│     ┌─────────────────────────────────────────┐                │
│     │  问题: 每次启动都从交易所获取历史数据    │                │
│     │        - 浪费 API 配额                   │                │
│     │        - 启动慢                          │                │
│     │        - 网络依赖                        │                │
│     │                                          │                │
│     │  解决: 本地 SQLite 缓存                  │                │
│     │        - 首次获取后本地存储              │                │
│     │        - 增量更新                        │                │
│     │        - 离线可用                        │                │
│     └─────────────────────────────────────────┘                │
│                                                                  │
│  2. 回测结果存储                                                │
│     ┌─────────────────────────────────────────┐                │
│     │  需求:                                   │                │
│     │  - 保存历史回测记录                      │                │
│     │  - 比较不同参数效果                      │                │
│     │  - 策略优化追踪                          │                │
│     │                                          │                │
│     │  存储:                                   │                │
│     │  - 策略名称/参数                         │                │
│     │  - 收益率/夏普/回撤                      │                │
│     │  - 交易记录                              │                │
│     └─────────────────────────────────────────┘                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### zig-sqlite 简介

[ sqlite.zig](https://github.com/vrischmann/zig-sqlite) 是 Zig 语言的 SQLite 绑定:
- 纯 Zig 实现，无 C 依赖
- 类型安全的 API
- 支持预编译语句
- 低内存开销

---

## 技术设计

### 数据模型

```
┌─────────────────────────────────────────────────────────────────┐
│                      数据库 Schema                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  candles                                                        │
│  ├── id: INTEGER PRIMARY KEY                                   │
│  ├── symbol: TEXT NOT NULL                                     │
│  ├── timeframe: TEXT NOT NULL (1m, 5m, 1h, 1d)                 │
│  ├── timestamp: INTEGER NOT NULL                               │
│  ├── open: REAL NOT NULL                                       │
│  ├── high: REAL NOT NULL                                       │
│  ├── low: REAL NOT NULL                                        │
│  ├── close: REAL NOT NULL                                      │
│  ├── volume: REAL NOT NULL                                     │
│  └── UNIQUE(symbol, timeframe, timestamp)                      │
│                                                                  │
│  backtest_results                                               │
│  ├── id: INTEGER PRIMARY KEY                                   │
│  ├── strategy: TEXT NOT NULL                                   │
│  ├── symbol: TEXT NOT NULL                                     │
│  ├── timeframe: TEXT NOT NULL                                  │
│  ├── start_time: INTEGER NOT NULL                              │
│  ├── end_time: INTEGER NOT NULL                                │
│  ├── total_return: REAL NOT NULL                               │
│  ├── sharpe_ratio: REAL NOT NULL                               │
│  ├── max_drawdown: REAL NOT NULL                               │
│  ├── total_trades: INTEGER NOT NULL                            │
│  ├── win_rate: REAL NOT NULL                                   │
│  ├── params_json: TEXT                                         │
│  └── created_at: INTEGER NOT NULL                              │
│                                                                  │
│  trades                                                         │
│  ├── id: INTEGER PRIMARY KEY                                   │
│  ├── backtest_id: INTEGER REFERENCES backtest_results(id)      │
│  ├── timestamp: INTEGER NOT NULL                               │
│  ├── side: TEXT NOT NULL (buy, sell)                           │
│  ├── price: REAL NOT NULL                                      │
│  ├── quantity: REAL NOT NULL                                   │
│  └── pnl: REAL                                                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 核心组件

```
┌─────────────────────────────────────────────────────────────────┐
│                      Storage 架构                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                     DataStore                             │  │
│  │                                                            │  │
│  │  ┌─────────────────────────────────────────────────────┐ │  │
│  │  │  db: sqlite.Database                                 │ │  │
│  │  │  allocator: Allocator                                │ │  │
│  │  └─────────────────────────────────────────────────────┘ │  │
│  │                                                            │  │
│  │  ┌─────────────────────────────────────────────────────┐ │  │
│  │  │  Methods:                                            │ │  │
│  │  │  • storeCandles(symbol, tf, candles)                 │ │  │
│  │  │  • loadCandles(symbol, tf, start, end) → []Candle    │ │  │
│  │  │  • getLatestTimestamp(symbol, tf) → ?i64             │ │  │
│  │  │  • storeBacktestResult(result)                       │ │  │
│  │  │  • loadBacktestResults(strategy) → []Result          │ │  │
│  │  │  • storeTrades(backtest_id, trades)                  │ │  │
│  │  └─────────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   CandleCache                             │  │
│  │  (结合内存缓存和 SQLite 持久化)                          │  │
│  │                                                            │  │
│  │  • get(symbol, tf, start, end) → []Candle                │  │
│  │  • set(symbol, tf, candles)                              │  │
│  │  • sync() (内存 → 磁盘)                                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### DataStore 实现

```zig
const std = @import("std");
const sqlite = @import("sqlite");
const Allocator = std.mem.Allocator;
const Decimal = @import("../core/decimal.zig").Decimal;
const Candle = @import("../core/candle.zig").Candle;

/// 数据存储管理器
pub const DataStore = struct {
    db: sqlite.Db,
    allocator: Allocator,

    // 预编译语句
    insert_candle_stmt: ?sqlite.Statement,
    select_candles_stmt: ?sqlite.Statement,

    const Self = @This();

    /// 打开或创建数据库
    pub fn open(allocator: Allocator, db_path: []const u8) !Self {
        var db = try sqlite.Db.open(.{
            .path = db_path,
            .mode = .ReadWrite,
        });

        // 创建表
        try initSchema(&db);

        return .{
            .db = db,
            .allocator = allocator,
            .insert_candle_stmt = null,
            .select_candles_stmt = null,
        };
    }

    pub fn close(self: *Self) void {
        if (self.insert_candle_stmt) |*stmt| stmt.deinit();
        if (self.select_candles_stmt) |*stmt| stmt.deinit();
        self.db.deinit();
    }

    /// 初始化数据库 Schema
    fn initSchema(db: *sqlite.Db) !void {
        try db.exec(
            \\CREATE TABLE IF NOT EXISTS candles (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  symbol TEXT NOT NULL,
            \\  timeframe TEXT NOT NULL,
            \\  timestamp INTEGER NOT NULL,
            \\  open REAL NOT NULL,
            \\  high REAL NOT NULL,
            \\  low REAL NOT NULL,
            \\  close REAL NOT NULL,
            \\  volume REAL NOT NULL,
            \\  UNIQUE(symbol, timeframe, timestamp)
            \\)
        , .{});

        try db.exec(
            \\CREATE INDEX IF NOT EXISTS idx_candles_lookup
            \\ON candles(symbol, timeframe, timestamp)
        , .{});

        try db.exec(
            \\CREATE TABLE IF NOT EXISTS backtest_results (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  strategy TEXT NOT NULL,
            \\  symbol TEXT NOT NULL,
            \\  timeframe TEXT NOT NULL,
            \\  start_time INTEGER NOT NULL,
            \\  end_time INTEGER NOT NULL,
            \\  total_return REAL NOT NULL,
            \\  sharpe_ratio REAL NOT NULL,
            \\  max_drawdown REAL NOT NULL,
            \\  total_trades INTEGER NOT NULL,
            \\  win_rate REAL NOT NULL,
            \\  params_json TEXT,
            \\  created_at INTEGER NOT NULL
            \\)
        , .{});

        try db.exec(
            \\CREATE TABLE IF NOT EXISTS trades (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  backtest_id INTEGER NOT NULL,
            \\  timestamp INTEGER NOT NULL,
            \\  side TEXT NOT NULL,
            \\  price REAL NOT NULL,
            \\  quantity REAL NOT NULL,
            \\  pnl REAL,
            \\  FOREIGN KEY(backtest_id) REFERENCES backtest_results(id)
            \\)
        , .{});
    }

    /// 存储 K 线数据
    pub fn storeCandles(
        self: *Self,
        symbol: []const u8,
        timeframe: []const u8,
        candles: []const Candle,
    ) !void {
        // 使用事务批量插入
        try self.db.exec("BEGIN TRANSACTION", .{});
        errdefer self.db.exec("ROLLBACK", .{}) catch {};

        var stmt = try self.db.prepare(
            \\INSERT OR REPLACE INTO candles
            \\(symbol, timeframe, timestamp, open, high, low, close, volume)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        );
        defer stmt.deinit();

        for (candles) |c| {
            stmt.bind(.{
                symbol,
                timeframe,
                c.timestamp,
                c.open.toFloat(),
                c.high.toFloat(),
                c.low.toFloat(),
                c.close.toFloat(),
                c.volume.toFloat(),
            }) catch |err| {
                std.log.err("Bind error: {}", .{err});
                return err;
            };

            _ = stmt.step() catch |err| {
                std.log.err("Step error: {}", .{err});
                return err;
            };
            stmt.reset();
        }

        try self.db.exec("COMMIT", .{});
    }

    /// 加载 K 线数据
    pub fn loadCandles(
        self: *Self,
        symbol: []const u8,
        timeframe: []const u8,
        start_ts: i64,
        end_ts: i64,
    ) ![]Candle {
        var stmt = try self.db.prepare(
            \\SELECT timestamp, open, high, low, close, volume
            \\FROM candles
            \\WHERE symbol = ? AND timeframe = ?
            \\  AND timestamp >= ? AND timestamp <= ?
            \\ORDER BY timestamp
        );
        defer stmt.deinit();

        stmt.bind(.{ symbol, timeframe, start_ts, end_ts }) catch |err| {
            return err;
        };

        var candles = std.ArrayList(Candle).init(self.allocator);
        errdefer candles.deinit();

        while (stmt.step()) |row| {
            try candles.append(.{
                .timestamp = row.timestamp,
                .open = Decimal.fromFloat(row.open),
                .high = Decimal.fromFloat(row.high),
                .low = Decimal.fromFloat(row.low),
                .close = Decimal.fromFloat(row.close),
                .volume = Decimal.fromFloat(row.volume),
            });
        } else |err| {
            return err;
        }

        return candles.toOwnedSlice();
    }

    /// 获取最新时间戳
    pub fn getLatestTimestamp(
        self: *Self,
        symbol: []const u8,
        timeframe: []const u8,
    ) !?i64 {
        var stmt = try self.db.prepare(
            \\SELECT MAX(timestamp) FROM candles
            \\WHERE symbol = ? AND timeframe = ?
        );
        defer stmt.deinit();

        stmt.bind(.{ symbol, timeframe }) catch |err| {
            return err;
        };

        if (stmt.step()) |row| {
            return row[0];
        } else |_| {
            return null;
        }
    }

    /// 存储回测结果
    pub fn storeBacktestResult(self: *Self, result: BacktestResult) !i64 {
        var stmt = try self.db.prepare(
            \\INSERT INTO backtest_results
            \\(strategy, symbol, timeframe, start_time, end_time,
            \\ total_return, sharpe_ratio, max_drawdown, total_trades,
            \\ win_rate, params_json, created_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        );
        defer stmt.deinit();

        stmt.bind(.{
            result.strategy,
            result.symbol,
            result.timeframe,
            result.start_time,
            result.end_time,
            result.total_return,
            result.sharpe_ratio,
            result.max_drawdown,
            result.total_trades,
            result.win_rate,
            result.params_json,
            std.time.milliTimestamp(),
        }) catch |err| {
            return err;
        };

        _ = stmt.step() catch |err| {
            return err;
        };

        return self.db.lastInsertRowId();
    }

    /// 加载回测结果
    pub fn loadBacktestResults(
        self: *Self,
        strategy: ?[]const u8,
        limit: u32,
    ) ![]BacktestResult {
        const query = if (strategy != null)
            \\SELECT * FROM backtest_results
            \\WHERE strategy = ?
            \\ORDER BY created_at DESC
            \\LIMIT ?
        else
            \\SELECT * FROM backtest_results
            \\ORDER BY created_at DESC
            \\LIMIT ?;

        var stmt = try self.db.prepare(query);
        defer stmt.deinit();

        if (strategy) |s| {
            stmt.bind(.{ s, limit }) catch |err| return err;
        } else {
            stmt.bind(.{limit}) catch |err| return err;
        }

        var results = std.ArrayList(BacktestResult).init(self.allocator);
        errdefer results.deinit();

        while (stmt.step()) |row| {
            try results.append(.{
                .id = row.id,
                .strategy = try self.allocator.dupe(u8, row.strategy),
                .symbol = try self.allocator.dupe(u8, row.symbol),
                .timeframe = try self.allocator.dupe(u8, row.timeframe),
                .start_time = row.start_time,
                .end_time = row.end_time,
                .total_return = row.total_return,
                .sharpe_ratio = row.sharpe_ratio,
                .max_drawdown = row.max_drawdown,
                .total_trades = row.total_trades,
                .win_rate = row.win_rate,
                .params_json = if (row.params_json) |p| try self.allocator.dupe(u8, p) else null,
            });
        } else |err| {
            return err;
        }

        return results.toOwnedSlice();
    }

    /// 数据库统计
    pub fn getStats(self: *Self) !DbStats {
        var candle_count: i64 = 0;
        var result_count: i64 = 0;

        {
            var stmt = try self.db.prepare("SELECT COUNT(*) FROM candles");
            defer stmt.deinit();
            if (stmt.step()) |row| {
                candle_count = row[0];
            } else |_| {}
        }

        {
            var stmt = try self.db.prepare("SELECT COUNT(*) FROM backtest_results");
            defer stmt.deinit();
            if (stmt.step()) |row| {
                result_count = row[0];
            } else |_| {}
        }

        return .{
            .candle_count = candle_count,
            .result_count = result_count,
        };
    }
};

pub const BacktestResult = struct {
    id: ?i64 = null,
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
    params_json: ?[]const u8 = null,
};

pub const DbStats = struct {
    candle_count: i64,
    result_count: i64,
};
```

### CandleCache 实现

```zig
/// 带缓存的 K 线存储
pub const CandleCache = struct {
    store: *DataStore,
    memory_cache: std.StringHashMap(CacheEntry),
    allocator: Allocator,
    max_memory_candles: usize,

    const CacheEntry = struct {
        candles: []Candle,
        last_access: i64,
    };

    const Self = @This();

    pub fn init(allocator: Allocator, store: *DataStore, max_candles: usize) Self {
        return .{
            .store = store,
            .memory_cache = std.StringHashMap(CacheEntry).init(allocator),
            .allocator = allocator,
            .max_memory_candles = max_candles,
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.memory_cache.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.candles);
        }
        self.memory_cache.deinit();
    }

    /// 获取 K 线 (优先内存，其次磁盘)
    pub fn get(
        self: *Self,
        symbol: []const u8,
        timeframe: []const u8,
        start: i64,
        end: i64,
    ) ![]Candle {
        const key = try std.fmt.allocPrint(
            self.allocator,
            "{s}:{s}",
            .{ symbol, timeframe },
        );
        defer self.allocator.free(key);

        // 检查内存缓存
        if (self.memory_cache.get(key)) |entry| {
            // TODO: 检查时间范围
            return entry.candles;
        }

        // 从磁盘加载
        const candles = try self.store.loadCandles(symbol, timeframe, start, end);

        // 加入内存缓存 (如果不超过限制)
        if (candles.len <= self.max_memory_candles) {
            const owned_key = try self.allocator.dupe(u8, key);
            try self.memory_cache.put(owned_key, .{
                .candles = candles,
                .last_access = std.time.milliTimestamp(),
            });
        }

        return candles;
    }

    /// 同步到磁盘
    pub fn sync(self: *Self) !void {
        var iter = self.memory_cache.iterator();
        while (iter.next()) |entry| {
            // 解析 key
            var parts = std.mem.split(u8, entry.key_ptr.*, ":");
            const symbol = parts.next() orelse continue;
            const timeframe = parts.next() orelse continue;

            try self.store.storeCandles(symbol, timeframe, entry.value_ptr.candles);
        }
    }
};
```

---

## 实现任务

### Task 1: 依赖集成 (Day 1)

- [ ] 添加 zig-sqlite 到 build.zig
- [ ] 验证编译和链接
- [ ] 创建 `src/storage/mod.zig`
- [ ] 基础连接测试

### Task 2: Schema 设计 (Day 1)

- [ ] 设计表结构
- [ ] 实现 initSchema
- [ ] 添加索引
- [ ] Schema 迁移机制

### Task 3: K 线存储 (Day 2)

- [ ] 实现 storeCandles
- [ ] 实现 loadCandles
- [ ] 实现 getLatestTimestamp
- [ ] 批量插入优化

### Task 4: 回测结果存储 (Day 2-3)

- [ ] 实现 storeBacktestResult
- [ ] 实现 loadBacktestResults
- [ ] 实现交易记录存储
- [ ] JSON 参数序列化

### Task 5: CandleCache (Day 3-4)

- [ ] 实现内存缓存
- [ ] 实现 LRU 淘汰
- [ ] 实现同步机制
- [ ] 性能测试

---

## 测试计划

### 单元测试

```zig
test "DataStore candle storage" {
    var store = try DataStore.open(testing.allocator, ":memory:");
    defer store.close();

    const candles = [_]Candle{
        .{ .timestamp = 1000, .open = Decimal.fromInt(100), ... },
        .{ .timestamp = 2000, .open = Decimal.fromInt(101), ... },
    };

    try store.storeCandles("ETH", "1h", &candles);

    const loaded = try store.loadCandles("ETH", "1h", 0, 3000);
    defer testing.allocator.free(loaded);

    try testing.expect(loaded.len == 2);
}

test "DataStore backtest result" {
    var store = try DataStore.open(testing.allocator, ":memory:");
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

    try testing.expect(id > 0);
}
```

### 性能测试

| 测试项 | 目标 | 验收标准 |
|--------|------|----------|
| 批量插入 | > 10,000 rows/s | 100K K线 < 10s |
| 查询延迟 | < 10ms | 1000 条记录 < 10ms |
| 内存占用 | < 50MB | 10万 K 线缓存 |

---

## 验收标准

### 功能验收

- [ ] K 线数据可存取
- [ ] 回测结果可存取
- [ ] 事务正确工作
- [ ] 内存缓存有效

### 性能验收

- [ ] 插入 > 10,000 rows/s
- [ ] 查询 < 10ms
- [ ] 内存使用合理

### 代码验收

- [ ] 完整单元测试
- [ ] 无内存泄漏
- [ ] 文档完整

---

## 文件结构

```
src/storage/
├── mod.zig           # 模块导出
├── data_store.zig    # DataStore 实现
├── candle_cache.zig  # CandleCache 实现
└── types.zig         # 共享类型

build.zig.zon         # 添加 zig-sqlite 依赖
```

---

## 依赖配置

```zig
// build.zig.zon
.dependencies = .{
    .sqlite = .{
        .url = "https://github.com/vrischmann/zig-sqlite/archive/refs/heads/master.tar.gz",
    },
},
```

---

**Story**: 036
**版本**: v0.7.0
**创建时间**: 2025-12-27
