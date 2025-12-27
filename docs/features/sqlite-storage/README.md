# SQLite Storage 数据持久化

> 使用 zig-sqlite 实现 K 线数据和回测结果的本地存储

**状态**: 📋 待开发
**版本**: v0.7.0
**Story**: [Story 036](../../stories/v0.7.0/STORY_036_SQLITE.md)
**依赖**: 无 (可并行开发)
**最后更新**: 2025-12-27

---

## 概述

集成 zig-sqlite 实现数据持久化，为量化策略提供本地数据缓存和回测结果管理能力。

### 为什么需要本地存储?

**K 线数据缓存**:
- 避免每次启动都从交易所获取历史数据
- 节省 API 配额
- 加快启动速度
- 支持离线回测

**回测结果存储**:
- 保存历史回测记录
- 比较不同参数效果
- 策略优化追踪

### 核心特性

- **K 线存储**: 多交易对、多时间周期
- **回测结果**: 完整性能指标和交易记录
- **增量更新**: 只获取新数据
- **内存缓存**: CandleCache 热数据缓存

---

## 快速开始

```zig
const DataStore = @import("storage/data_store.zig").DataStore;

// 打开或创建数据库
var store = try DataStore.open(allocator, "data/zigquant.db");
defer store.close();

// 存储 K 线
try store.storeCandles("ETH-USD", .@"1h", candles);

// 加载 K 线
const candles = try store.loadCandles(
    "ETH-USD",
    .@"1h",
    start_time,
    end_time,
);
defer allocator.free(candles);

// 存储回测结果
try store.storeBacktestResult(result);

// 查询历史回测
const results = try store.loadBacktestResults("DualMA");
```

---

## 数据库 Schema

```sql
-- K 线数据表
CREATE TABLE candles (
    id INTEGER PRIMARY KEY,
    symbol TEXT NOT NULL,
    timeframe TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    open REAL NOT NULL,
    high REAL NOT NULL,
    low REAL NOT NULL,
    close REAL NOT NULL,
    volume REAL NOT NULL,
    UNIQUE(symbol, timeframe, timestamp)
);

-- 回测结果表
CREATE TABLE backtest_results (
    id INTEGER PRIMARY KEY,
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
    params_json TEXT,
    created_at INTEGER NOT NULL
);

-- 交易记录表
CREATE TABLE trades (
    id INTEGER PRIMARY KEY,
    backtest_id INTEGER REFERENCES backtest_results(id),
    timestamp INTEGER NOT NULL,
    side TEXT NOT NULL,
    price REAL NOT NULL,
    quantity REAL NOT NULL,
    pnl REAL
);
```

---

## 核心 API

### DataStore

```zig
pub const DataStore = struct {
    /// 打开数据库
    pub fn open(allocator: Allocator, path: []const u8) !DataStore;

    /// 关闭数据库
    pub fn close(self: *DataStore) void;

    /// 存储 K 线数据
    pub fn storeCandles(self: *DataStore, symbol: []const u8,
                        timeframe: Timeframe, candles: []const Candle) !void;

    /// 加载 K 线数据
    pub fn loadCandles(self: *DataStore, symbol: []const u8,
                       timeframe: Timeframe, start: i64, end: i64) ![]Candle;

    /// 获取最新时间戳
    pub fn getLatestTimestamp(self: *DataStore, symbol: []const u8,
                              timeframe: Timeframe) !?i64;

    /// 存储回测结果
    pub fn storeBacktestResult(self: *DataStore, result: BacktestResult) !u64;

    /// 加载回测结果
    pub fn loadBacktestResults(self: *DataStore, strategy: []const u8) ![]BacktestResult;
};
```

### CandleCache

```zig
pub const CandleCache = struct {
    /// 获取 K 线 (优先内存，其次磁盘)
    pub fn get(self: *CandleCache, symbol: []const u8,
               timeframe: Timeframe, start: i64, end: i64) ![]Candle;

    /// 设置 K 线 (写入内存和磁盘)
    pub fn set(self: *CandleCache, symbol: []const u8,
               timeframe: Timeframe, candles: []const Candle) !void;

    /// 同步到磁盘
    pub fn sync(self: *CandleCache) !void;
};
```

---

## 相关文档

- [API 参考](./api.md)
- [实现细节](./implementation.md)
- [测试文档](./testing.md)
- [Bug 追踪](./bugs.md)
- [变更日志](./changelog.md)

---

## 性能指标

| 指标 | 目标值 |
|------|--------|
| 单条插入 | < 1ms |
| 批量插入 (1000条) | < 100ms |
| 查询延迟 | < 10ms |
| 数据库大小 | ~100MB/年/交易对 |

---

*Last updated: 2025-12-27*
