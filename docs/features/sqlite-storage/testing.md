# SQLite Storage 测试文档

> 数据持久化模块的测试策略和用例

**版本**: v0.7.0
**状态**: 📋 待开发
**最后更新**: 2025-12-27

---

## 测试概述

### 测试范围

| 类别 | 描述 | 优先级 |
|------|------|--------|
| 基本 CRUD | K 线和回测结果的增删改查 | P0 |
| 数据完整性 | Decimal 精度、时间戳顺序 | P0 |
| 批量操作 | 事务和批量插入 | P1 |
| 缓存功能 | LRU 缓存命中/淘汰 | P1 |
| 边界条件 | 空数据、大数据量 | P1 |
| 并发访问 | 多线程读写 | P2 |
| 性能测试 | 延迟和吞吐量 | P2 |

### 测试文件

```
src/storage/tests/
├── data_store_test.zig       # 主存储测试
├── candle_store_test.zig     # K 线存储测试
├── backtest_store_test.zig   # 回测结果测试
├── cache_test.zig            # 缓存测试
├── migration_test.zig        # 迁移测试
└── benchmark_test.zig        # 性能基准测试
```

---

## 单元测试

### DataStore 基本测试

```zig
const testing = @import("std").testing;
const DataStore = @import("../data_store.zig").DataStore;
const Decimal = @import("decimal").Decimal;

test "DataStore: open and close" {
    const allocator = testing.allocator;

    // 使用内存数据库
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    // 验证连接有效
    try testing.expect(store.isConnected());
}

test "DataStore: create with file" {
    const allocator = testing.allocator;
    const path = "/tmp/test_zigquant.db";

    // 清理旧文件
    std.fs.deleteFileAbsolute(path) catch {};

    var store = try DataStore.open(allocator, path);
    store.close();

    // 验证文件创建
    const file = try std.fs.openFileAbsolute(path, .{});
    file.close();

    // 清理
    try std.fs.deleteFileAbsolute(path);
}
```

### K 线存储测试

```zig
test "storeCandles: single candle" {
    const allocator = testing.allocator;
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    const candle = Candle{
        .timestamp = 1000000,
        .open = Decimal.fromFloat(100.0),
        .high = Decimal.fromFloat(105.0),
        .low = Decimal.fromFloat(99.0),
        .close = Decimal.fromFloat(102.0),
        .volume = Decimal.fromFloat(1000.0),
    };

    try store.storeCandles("ETH-USD", .@"1h", &[_]Candle{candle});

    const loaded = try store.loadCandles("ETH-USD", .@"1h", 0, 2000000);
    defer allocator.free(loaded);

    try testing.expectEqual(@as(usize, 1), loaded.len);
    try testing.expect(loaded[0].open.eq(candle.open));
}

test "storeCandles: batch insert" {
    const allocator = testing.allocator;
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    // 创建 1000 个 K 线
    var candles: [1000]Candle = undefined;
    for (&candles, 0..) |*c, i| {
        c.* = Candle{
            .timestamp = @intCast(i * 3600_000_000_000), // 每小时
            .open = Decimal.fromFloat(100.0 + @as(f64, @floatFromInt(i)) * 0.1),
            .high = Decimal.fromFloat(105.0),
            .low = Decimal.fromFloat(99.0),
            .close = Decimal.fromFloat(102.0),
            .volume = Decimal.fromFloat(1000.0),
        };
    }

    try store.storeCandles("ETH-USD", .@"1h", &candles);

    const count = try store.countCandles("ETH-USD", .@"1h");
    try testing.expectEqual(@as(u64, 1000), count);
}

test "storeCandles: upsert behavior" {
    const allocator = testing.allocator;
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    // 插入初始数据
    const candle1 = Candle{
        .timestamp = 1000000,
        .open = Decimal.fromFloat(100.0),
        .high = Decimal.fromFloat(105.0),
        .low = Decimal.fromFloat(99.0),
        .close = Decimal.fromFloat(102.0),
        .volume = Decimal.fromFloat(1000.0),
    };
    try store.storeCandles("ETH-USD", .@"1h", &[_]Candle{candle1});

    // 更新相同时间戳的数据
    const candle2 = Candle{
        .timestamp = 1000000,
        .open = Decimal.fromFloat(101.0), // 不同的值
        .high = Decimal.fromFloat(106.0),
        .low = Decimal.fromFloat(100.0),
        .close = Decimal.fromFloat(103.0),
        .volume = Decimal.fromFloat(1500.0),
    };
    try store.storeCandles("ETH-USD", .@"1h", &[_]Candle{candle2});

    // 应该只有一条记录
    const count = try store.countCandles("ETH-USD", .@"1h");
    try testing.expectEqual(@as(u64, 1), count);

    // 值应该是更新后的
    const loaded = try store.loadCandles("ETH-USD", .@"1h", 0, 2000000);
    defer allocator.free(loaded);

    try testing.expect(loaded[0].open.eq(Decimal.fromFloat(101.0)));
}

test "loadCandles: time range filter" {
    const allocator = testing.allocator;
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    // 插入跨时间范围的数据
    var candles: [10]Candle = undefined;
    for (&candles, 0..) |*c, i| {
        c.* = Candle{
            .timestamp = @intCast(i * 1000000),
            .open = Decimal.fromFloat(100.0),
            .high = Decimal.fromFloat(105.0),
            .low = Decimal.fromFloat(99.0),
            .close = Decimal.fromFloat(102.0),
            .volume = Decimal.fromFloat(1000.0),
        };
    }
    try store.storeCandles("ETH-USD", .@"1h", &candles);

    // 查询中间范围
    const loaded = try store.loadCandles("ETH-USD", .@"1h", 3000000, 7000000);
    defer allocator.free(loaded);

    try testing.expectEqual(@as(usize, 5), loaded.len); // 索引 3, 4, 5, 6, 7
}

test "getLatestTimestamp: empty table" {
    const allocator = testing.allocator;
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    const latest = try store.getLatestTimestamp("ETH-USD", .@"1h");
    try testing.expect(latest == null);
}

test "getLatestTimestamp: with data" {
    const allocator = testing.allocator;
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    const candles = [_]Candle{
        .{ .timestamp = 1000000, .open = Decimal.fromFloat(100.0), .high = Decimal.fromFloat(100.0), .low = Decimal.fromFloat(100.0), .close = Decimal.fromFloat(100.0), .volume = Decimal.fromFloat(100.0) },
        .{ .timestamp = 2000000, .open = Decimal.fromFloat(100.0), .high = Decimal.fromFloat(100.0), .low = Decimal.fromFloat(100.0), .close = Decimal.fromFloat(100.0), .volume = Decimal.fromFloat(100.0) },
        .{ .timestamp = 3000000, .open = Decimal.fromFloat(100.0), .high = Decimal.fromFloat(100.0), .low = Decimal.fromFloat(100.0), .close = Decimal.fromFloat(100.0), .volume = Decimal.fromFloat(100.0) },
    };
    try store.storeCandles("ETH-USD", .@"1h", &candles);

    const latest = try store.getLatestTimestamp("ETH-USD", .@"1h");
    try testing.expect(latest != null);
    try testing.expectEqual(@as(i64, 3000000), latest.?);
}
```

### 回测结果测试

```zig
test "storeBacktestResult: basic" {
    const allocator = testing.allocator;
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    const result = BacktestResult{
        .strategy = "DualMA",
        .symbol = "ETH-USD",
        .timeframe = .@"1h",
        .start_time = 0,
        .end_time = 1000000,
        .total_return = 0.15,
        .sharpe_ratio = 1.5,
        .max_drawdown = 0.10,
        .total_trades = 50,
        .win_rate = 0.6,
    };

    const id = try store.storeBacktestResult(result);
    try testing.expect(id > 0);
}

test "loadBacktestResults: filter by strategy" {
    const allocator = testing.allocator;
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    // 插入多个策略结果
    _ = try store.storeBacktestResult(.{ .strategy = "DualMA", .symbol = "ETH-USD", .timeframe = .@"1h", .start_time = 0, .end_time = 1000, .total_return = 0.1, .sharpe_ratio = 1.0, .max_drawdown = 0.05, .total_trades = 10, .win_rate = 0.5 });
    _ = try store.storeBacktestResult(.{ .strategy = "DualMA", .symbol = "BTC-USD", .timeframe = .@"1h", .start_time = 0, .end_time = 1000, .total_return = 0.2, .sharpe_ratio = 1.5, .max_drawdown = 0.08, .total_trades = 15, .win_rate = 0.6 });
    _ = try store.storeBacktestResult(.{ .strategy = "RSI", .symbol = "ETH-USD", .timeframe = .@"1h", .start_time = 0, .end_time = 1000, .total_return = 0.05, .sharpe_ratio = 0.8, .max_drawdown = 0.03, .total_trades = 5, .win_rate = 0.4 });

    // 只获取 DualMA 结果
    const results = try store.loadBacktestResults("DualMA", null);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 2), results.len);
}
```

### 数据完整性测试

```zig
test "Decimal precision preserved" {
    const allocator = testing.allocator;
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    // 使用高精度值
    const precise_value = Decimal.parse("1234.567890123456") catch unreachable;

    const candle = Candle{
        .timestamp = 1000000,
        .open = precise_value,
        .high = precise_value,
        .low = precise_value,
        .close = precise_value,
        .volume = precise_value,
    };
    try store.storeCandles("TEST", .@"1h", &[_]Candle{candle});

    const loaded = try store.loadCandles("TEST", .@"1h", 0, 2000000);
    defer allocator.free(loaded);

    // 精度应该保持
    try testing.expect(loaded[0].open.eq(precise_value));
}

test "timestamp ordering" {
    const allocator = testing.allocator;
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    // 乱序插入
    const candles = [_]Candle{
        .{ .timestamp = 3000000, .open = Decimal.fromFloat(103.0), .high = Decimal.fromFloat(103.0), .low = Decimal.fromFloat(103.0), .close = Decimal.fromFloat(103.0), .volume = Decimal.fromFloat(100.0) },
        .{ .timestamp = 1000000, .open = Decimal.fromFloat(101.0), .high = Decimal.fromFloat(101.0), .low = Decimal.fromFloat(101.0), .close = Decimal.fromFloat(101.0), .volume = Decimal.fromFloat(100.0) },
        .{ .timestamp = 2000000, .open = Decimal.fromFloat(102.0), .high = Decimal.fromFloat(102.0), .low = Decimal.fromFloat(102.0), .close = Decimal.fromFloat(102.0), .volume = Decimal.fromFloat(100.0) },
    };
    try store.storeCandles("TEST", .@"1h", &candles);

    // 加载应该按时间排序
    const loaded = try store.loadCandles("TEST", .@"1h", 0, 4000000);
    defer allocator.free(loaded);

    try testing.expectEqual(@as(i64, 1000000), loaded[0].timestamp);
    try testing.expectEqual(@as(i64, 2000000), loaded[1].timestamp);
    try testing.expectEqual(@as(i64, 3000000), loaded[2].timestamp);
}
```

---

## 缓存测试

```zig
test "CandleCache: hit" {
    const allocator = testing.allocator;
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    var cache = CandleCache.init(allocator, &store, 10); // 10MB
    defer cache.deinit();

    // 预热缓存
    const candle = Candle{ .timestamp = 1000000, .open = Decimal.fromFloat(100.0), .high = Decimal.fromFloat(100.0), .low = Decimal.fromFloat(100.0), .close = Decimal.fromFloat(100.0), .volume = Decimal.fromFloat(100.0) };
    try store.storeCandles("TEST", .@"1h", &[_]Candle{candle});

    // 第一次访问 (miss)
    _ = try cache.get("TEST", .@"1h", 0, 2000000);

    // 第二次访问 (hit)
    _ = try cache.get("TEST", .@"1h", 0, 2000000);

    const stats = cache.getStats();
    try testing.expectEqual(@as(u64, 1), stats.hits);
    try testing.expectEqual(@as(u64, 1), stats.misses);
}

test "CandleCache: eviction" {
    const allocator = testing.allocator;
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    // 非常小的缓存
    var cache = CandleCache.init(allocator, &store, 1); // 1MB
    cache.max_entries = 2; // 只允许 2 个条目
    defer cache.deinit();

    // 插入 3 个不同的数据集
    for (0..3) |i| {
        const symbol = switch (i) {
            0 => "A",
            1 => "B",
            else => "C",
        };
        const candle = Candle{ .timestamp = 1000000, .open = Decimal.fromFloat(100.0), .high = Decimal.fromFloat(100.0), .low = Decimal.fromFloat(100.0), .close = Decimal.fromFloat(100.0), .volume = Decimal.fromFloat(100.0) };
        try store.storeCandles(symbol, .@"1h", &[_]Candle{candle});
        _ = try cache.get(symbol, .@"1h", 0, 2000000);
    }

    // 缓存条目数应该 <= 2
    const stats = cache.getStats();
    try testing.expect(stats.entry_count <= 2);
}
```

---

## 性能测试

```zig
test "benchmark: insert 10000 candles" {
    const allocator = testing.allocator;
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    var candles: [10000]Candle = undefined;
    for (&candles, 0..) |*c, i| {
        c.* = Candle{
            .timestamp = @intCast(i * 3600_000_000_000),
            .open = Decimal.fromFloat(100.0),
            .high = Decimal.fromFloat(105.0),
            .low = Decimal.fromFloat(99.0),
            .close = Decimal.fromFloat(102.0),
            .volume = Decimal.fromFloat(1000.0),
        };
    }

    var timer = std.time.Timer{};
    timer.reset();

    try store.storeCandles("ETH-USD", .@"1h", &candles);

    const elapsed_ms = timer.read() / 1_000_000;

    std.debug.print("\n10000 candles insert: {}ms\n", .{elapsed_ms});
    try testing.expect(elapsed_ms < 1000); // 应该 < 1秒
}

test "benchmark: query 1000 candles" {
    const allocator = testing.allocator;
    var store = try DataStore.open(allocator, ":memory:");
    defer store.close();

    // 预插入数据
    var candles: [10000]Candle = undefined;
    for (&candles, 0..) |*c, i| {
        c.* = Candle{
            .timestamp = @intCast(i * 3600_000_000_000),
            .open = Decimal.fromFloat(100.0),
            .high = Decimal.fromFloat(105.0),
            .low = Decimal.fromFloat(99.0),
            .close = Decimal.fromFloat(102.0),
            .volume = Decimal.fromFloat(1000.0),
        };
    }
    try store.storeCandles("ETH-USD", .@"1h", &candles);

    var timer = std.time.Timer{};
    timer.reset();

    const loaded = try store.loadCandles(
        "ETH-USD",
        .@"1h",
        1000 * 3600_000_000_000,
        2000 * 3600_000_000_000,
    );
    defer allocator.free(loaded);

    const elapsed_us = timer.read() / 1000;

    std.debug.print("\nQuery 1000 candles: {}μs\n", .{elapsed_us});
    try testing.expect(elapsed_us < 10_000); // 应该 < 10ms
}
```

---

## 运行测试

```bash
# 运行所有存储测试
zig build test -- --test-filter="storage"

# 运行特定测试
zig build test -- --test-filter="storeCandles"

# 运行性能测试
zig build test -- --test-filter="benchmark"
```

---

## 测试覆盖率目标

| 模块 | 目标覆盖率 |
|------|------------|
| data_store.zig | > 90% |
| candle_store.zig | > 95% |
| cache.zig | > 85% |

---

*Last updated: 2025-12-27*
