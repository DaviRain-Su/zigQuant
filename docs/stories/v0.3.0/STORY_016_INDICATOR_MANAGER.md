# Story: IndicatorManager 和缓存优化

**ID**: `STORY-016`
**版本**: `v0.3.0`
**创建日期**: 2025-12-25
**状态**: 📋 待开始
**优先级**: P0 (必须)
**预计工时**: 1 天

---

## 📋 需求描述

### 用户故事
作为策略开发者，我希望有一个智能的指标管理器，以便我可以复用已计算的指标结果，避免重复计算，提高策略执行效率。

### 背景
在回测和实时交易中，多个策略或同一策略的不同部分可能需要相同的技术指标。例如：
- 双均线策略需要 SMA(10) 和 SMA(20)
- MACD 策略内部使用 EMA(12) 和 EMA(26)
- 多个策略同时使用 RSI(14)

如果每次都重新计算，会造成大量性能浪费。IndicatorManager 将提供：
- **缓存机制**: 相同参数的指标只计算一次
- **生命周期管理**: 自动管理指标结果的内存
- **Candles 容器**: 封装 K线数据和指标数据
- **智能失效**: 数据更新时自动失效缓存

### 范围
- **包含**:
  - IndicatorManager 核心实现
  - Candles 容器实现
  - 缓存键生成和管理
  - 缓存命中率统计
  - 单元测试和性能测试
  - 与 Story 015 的指标库集成

- **不包含**:
  - LRU 缓存策略（后续优化）
  - 分布式缓存
  - 持久化缓存
  - 可视化缓存状态

---

## 🎯 验收标准

- [ ] **AC1**: IndicatorManager 实现完整
  - `getOrCalculate()` 方法
  - `invalidate()` 方法
  - `clear()` 方法
  - 统计信息（命中率、缓存大小）

- [ ] **AC2**: Candles 容器功能完整
  - 存储 K线数据
  - 存储关联的指标数据
  - 添加/获取指标便捷方法
  - 资源管理正确

- [ ] **AC3**: 缓存机制正确
  - 相同参数的指标只计算一次
  - 缓存键生成准确（包含指标名称和参数）
  - 内存管理正确（无泄漏）

- [ ] **AC4**: 缓存命中率达标
  - 典型回测场景缓存命中率 > 90%
  - 实时数据更新场景正确失效缓存

- [ ] **AC5**: 性能提升明显
  - 缓存命中时获取指标耗时 < 0.1ms
  - 重复计算相同指标性能提升 > 90%

- [ ] **AC6**: 与指标库集成良好
  - 支持所有 Story 015 的指标
  - 提供统一的调用接口
  - 错误处理完善

- [ ] **AC7**: 单元测试覆盖率 > 85%
  - 缓存命中测试
  - 缓存失效测试
  - 内存泄漏测试
  - 并发访问测试（如适用）

- [ ] **AC8**: 编译通过，无警告

---

## 🔧 技术设计

### 架构概览

```
IndicatorManager
    ├── Cache (HashMap)
    │   ├── Key: "SMA_20_BTC/USDT_1h"
    │   └── Value: []Decimal
    │
    ├── Statistics
    │   ├── cache_hits
    │   ├── cache_misses
    │   └── total_requests
    │
    └── Candles Container
        ├── data: []Candle
        └── indicators: HashMap<String, []Decimal>
```

### 数据结构

#### 1. Candles 容器 (candles.zig)

```zig
const std = @import("std");
const Decimal = @import("../types/decimal.zig").Decimal;
const Candle = @import("../types/market.zig").Candle;
const TradingPair = @import("../types/market.zig").TradingPair;
const Timeframe = @import("../types/market.zig").Timeframe;

/// K线数据容器 - 封装 K线和关联的指标数据
pub const Candles = struct {
    allocator: std.mem.Allocator,

    /// 原始 K线数据
    data: []Candle,

    /// 交易对
    pair: TradingPair,

    /// 时间周期
    timeframe: Timeframe,

    /// 关联的指标数据
    /// Key: 指标名称（如 "sma_20", "rsi_14"）
    /// Value: 指标值数组
    indicators: std.StringHashMap([]Decimal),

    pub fn init(
        allocator: std.mem.Allocator,
        data: []Candle,
        pair: TradingPair,
        timeframe: Timeframe,
    ) !Candles {
        return Candles{
            .allocator = allocator,
            .data = data,
            .pair = pair,
            .timeframe = timeframe,
            .indicators = std.StringHashMap([]Decimal).init(allocator),
        };
    }

    pub fn deinit(self: *Candles) void {
        // 释放所有指标数据
        var iter = self.indicators.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.indicators.deinit();

        // 注意: data 不在这里释放，由调用者管理
    }

    /// 添加指标数据
    pub fn addIndicator(self: *Candles, name: []const u8, values: []Decimal) !void {
        if (values.len != self.data.len) {
            return error.IndicatorLengthMismatch;
        }

        // 复制名称和数据
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        try self.indicators.put(name_copy, values);
    }

    /// 获取指标数据
    pub fn getIndicator(self: *Candles, name: []const u8) ?[]Decimal {
        return self.indicators.get(name);
    }

    /// 检查指标是否存在
    pub fn hasIndicator(self: *Candles, name: []const u8) bool {
        return self.indicators.contains(name);
    }

    /// 获取指标数量
    pub fn getIndicatorCount(self: *Candles) usize {
        return self.indicators.count();
    }

    /// 清除所有指标
    pub fn clearIndicators(self: *Candles) void {
        var iter = self.indicators.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.indicators.clearRetainingCapacity();
    }
};
```

#### 2. IndicatorManager (manager.zig)

```zig
const std = @import("std");
const Decimal = @import("../../types/decimal.zig").Decimal;
const Candle = @import("../../types/market.zig").Candle;
const Candles = @import("../candles.zig").Candles;
const IIndicator = @import("interface.zig").IIndicator;

/// 缓存统计信息
pub const CacheStats = struct {
    cache_hits: u64,
    cache_misses: u64,
    total_requests: u64,

    pub fn hitRate(self: CacheStats) f64 {
        if (self.total_requests == 0) return 0.0;
        return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(self.total_requests));
    }

    pub fn reset(self: *CacheStats) void {
        self.cache_hits = 0;
        self.cache_misses = 0;
        self.total_requests = 0;
    }
};

/// 指标管理器 - 缓存和复用指标计算结果
pub const IndicatorManager = struct {
    allocator: std.mem.Allocator,

    /// 指标缓存
    /// Key: 缓存键（如 "SMA_20_BTC/USDT_1h_<hash>"）
    /// Value: 指标值数组
    cache: std.StringHashMap([]Decimal),

    /// 缓存统计
    stats: CacheStats,

    pub fn init(allocator: std.mem.Allocator) !IndicatorManager {
        return IndicatorManager{
            .allocator = allocator,
            .cache = std.StringHashMap([]Decimal).init(allocator),
            .stats = CacheStats{
                .cache_hits = 0,
                .cache_misses = 0,
                .total_requests = 0,
            },
        };
    }

    pub fn deinit(self: *IndicatorManager) void {
        self.clear();
        self.cache.deinit();
    }

    /// 获取或计算指标
    /// @param name - 指标名称
    /// @param indicator - 指标实例
    /// @param candles - K线数据
    /// @return 指标值数组（会被缓存）
    pub fn getOrCalculate(
        self: *IndicatorManager,
        name: []const u8,
        indicator: IIndicator,
        candles: *Candles,
    ) ![]Decimal {
        self.stats.total_requests += 1;

        // 生成缓存键
        const cache_key = try self.generateCacheKey(
            name,
            indicator,
            candles.pair,
            candles.timeframe,
            candles.data,
        );
        defer self.allocator.free(cache_key);

        // 检查缓存
        if (self.cache.get(cache_key)) |cached| {
            self.stats.cache_hits += 1;
            return cached;
        }

        // 缓存未命中，计算指标
        self.stats.cache_misses += 1;
        const values = try indicator.calculate(candles.data);

        // 存入缓存
        const key_copy = try self.allocator.dupe(u8, cache_key);
        try self.cache.put(key_copy, values);

        // 同时存入 Candles 容器
        try candles.addIndicator(name, values);

        return values;
    }

    /// 生成缓存键
    /// 格式: "<indicator_name>_<params>_<pair>_<timeframe>_<data_hash>"
    fn generateCacheKey(
        self: *IndicatorManager,
        name: []const u8,
        indicator: IIndicator,
        pair: TradingPair,
        timeframe: Timeframe,
        candles: []const Candle,
    ) ![]u8 {
        // 计算数据哈希（使用第一根和最后一根 K线的时间戳）
        const data_hash = if (candles.len > 0)
            @as(u64, @intCast(candles[0].timestamp.unix ^ candles[candles.len - 1].timestamp.unix))
        else
            0;

        // 生成键: "SMA_20_BTC/USDT_1h_123456"
        return try std.fmt.allocPrint(
            self.allocator,
            "{s}_{d}_{s}_{s}_{d}",
            .{
                name,
                indicator.getRequiredCandles(),
                pair.toString(),
                @tagName(timeframe),
                data_hash,
            },
        );
    }

    /// 失效缓存（数据更新时调用）
    pub fn invalidate(self: *IndicatorManager, pattern: []const u8) void {
        var keys_to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer keys_to_remove.deinit();

        // 查找匹配的键
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            if (std.mem.indexOf(u8, entry.key_ptr.*, pattern) != null) {
                keys_to_remove.append(entry.key_ptr.*) catch continue;
            }
        }

        // 移除缓存项
        for (keys_to_remove.items) |key| {
            if (self.cache.fetchRemove(key)) |kv| {
                self.allocator.free(kv.value);
                self.allocator.free(kv.key);
            }
        }
    }

    /// 清空所有缓存
    pub fn clear(self: *IndicatorManager) void {
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.cache.clearRetainingCapacity();
        self.stats.reset();
    }

    /// 获取缓存统计信息
    pub fn getStats(self: *IndicatorManager) CacheStats {
        return self.stats;
    }

    /// 获取缓存大小
    pub fn getCacheSize(self: *IndicatorManager) usize {
        return self.cache.count();
    }

    /// 预热缓存（批量计算常用指标）
    pub fn warmup(
        self: *IndicatorManager,
        candles: *Candles,
        indicators: []struct {
            name: []const u8,
            indicator: IIndicator,
        },
    ) !void {
        for (indicators) |item| {
            _ = try self.getOrCalculate(item.name, item.indicator, candles);
        }
    }
};
```

#### 3. 便捷辅助函数 (helpers.zig)

```zig
const std = @import("std");
const Candles = @import("candles.zig").Candles;
const IndicatorManager = @import("indicators/manager.zig").IndicatorManager;
const SMA = @import("indicators/sma.zig").SMA;
const EMA = @import("indicators/ema.zig").EMA;
const RSI = @import("indicators/rsi.zig").RSI;
const MACD = @import("indicators/macd.zig").MACD;
const BollingerBands = @import("indicators/bollinger.zig").BollingerBands;

/// 便捷方法: 获取或计算 SMA
pub fn getSMA(
    manager: *IndicatorManager,
    candles: *Candles,
    period: u32,
) ![]Decimal {
    const sma = try SMA.init(manager.allocator, period);
    defer sma.toIndicator().deinit();

    const name = try std.fmt.allocPrint(manager.allocator, "sma_{d}", .{period});
    defer manager.allocator.free(name);

    return try manager.getOrCalculate(name, sma.toIndicator(), candles);
}

/// 便捷方法: 获取或计算 EMA
pub fn getEMA(
    manager: *IndicatorManager,
    candles: *Candles,
    period: u32,
) ![]Decimal {
    const ema = try EMA.init(manager.allocator, period);
    defer ema.toIndicator().deinit();

    const name = try std.fmt.allocPrint(manager.allocator, "ema_{d}", .{period});
    defer manager.allocator.free(name);

    return try manager.getOrCalculate(name, ema.toIndicator(), candles);
}

/// 便捷方法: 获取或计算 RSI
pub fn getRSI(
    manager: *IndicatorManager,
    candles: *Candles,
    period: u32,
) ![]Decimal {
    const rsi = try RSI.init(manager.allocator, period);
    defer rsi.toIndicator().deinit();

    const name = try std.fmt.allocPrint(manager.allocator, "rsi_{d}", .{period});
    defer manager.allocator.free(name);

    return try manager.getOrCalculate(name, rsi.toIndicator(), candles);
}

/// 便捷方法: 获取或计算 MACD
pub fn getMACD(
    manager: *IndicatorManager,
    candles: *Candles,
    fast: u32,
    slow: u32,
    signal: u32,
) !MACD.MACDResult {
    const macd = try MACD.init(manager.allocator, fast, slow, signal);
    defer macd.deinit();

    return try macd.calculate(candles.data);
}

/// 便捷方法: 获取或计算 Bollinger Bands
pub fn getBollingerBands(
    manager: *IndicatorManager,
    candles: *Candles,
    period: u32,
    std_dev: f64,
) !BollingerBands.BollingerBandsResult {
    const bb = try BollingerBands.init(manager.allocator, period, std_dev);
    defer bb.deinit();

    return try bb.calculate(candles.data);
}
```

### 文件结构

```
src/strategy/
├── candles.zig                    # Candles 容器
├── candles_test.zig               # Candles 测试
├── helpers.zig                    # 便捷辅助函数
└── indicators/
    ├── manager.zig                # IndicatorManager
    ├── manager_test.zig           # Manager 测试
    ├── performance_test.zig       # 性能测试
    └── ...（Story 015 的指标）
```

---

## 📝 任务分解

### Phase 1: 容器和管理器实现 (0.5天)
- [ ] 任务 1.1: 实现 Candles 容器
  - 基础数据结构
  - 指标存储和获取
  - 资源管理
- [ ] 任务 1.2: 实现 IndicatorManager
  - 缓存键生成
  - 缓存查询和存储
  - 统计信息
- [ ] 任务 1.3: 编写单元测试

### Phase 2: 优化和辅助功能 (0.25天)
- [ ] 任务 2.1: 实现缓存失效逻辑
  - 模式匹配失效
  - 清空所有缓存
- [ ] 任务 2.2: 实现便捷辅助函数
  - getSMA, getEMA, getRSI 等
  - 统一错误处理
- [ ] 任务 2.3: 编写集成测试

### Phase 3: 性能测试和文档 (0.25天)
- [ ] 任务 3.1: 性能测试
  - 缓存命中率测试
  - 性能提升测试
  - 内存使用测试
- [ ] 任务 3.2: 更新文档
  - API 文档
  - 使用示例
  - 最佳实践

---

## 🧪 测试策略

### 单元测试

#### candles_test.zig

```zig
const std = @import("std");
const testing = std.testing;
const Candles = @import("candles.zig").Candles;
const Decimal = @import("../types/decimal.zig").Decimal;

test "Candles: create and manage indicators" {
    const allocator = testing.allocator;

    const candles_data = try createTestCandles(allocator, 100);
    defer allocator.free(candles_data);

    var candles = try Candles.init(
        allocator,
        candles_data,
        TradingPair.init("BTC", "USDT"),
        .m15,
    );
    defer candles.deinit();

    // 添加指标
    const sma_values = try allocator.alloc(Decimal, 100);
    try candles.addIndicator("sma_20", sma_values);

    // 获取指标
    const retrieved = candles.getIndicator("sma_20");
    try testing.expect(retrieved != null);
    try testing.expectEqual(@as(usize, 100), retrieved.?.len);

    // 检查指标存在
    try testing.expect(candles.hasIndicator("sma_20"));
    try testing.expect(!candles.hasIndicator("ema_10"));

    // 指标数量
    try testing.expectEqual(@as(usize, 1), candles.getIndicatorCount());
}

test "Candles: reject mismatched indicator length" {
    const allocator = testing.allocator;

    const candles_data = try createTestCandles(allocator, 100);
    defer allocator.free(candles_data);

    var candles = try Candles.init(
        allocator,
        candles_data,
        TradingPair.init("BTC", "USDT"),
        .m15,
    );
    defer candles.deinit();

    // 长度不匹配的指标
    const bad_values = try allocator.alloc(Decimal, 50);  // 应该是 100
    defer allocator.free(bad_values);

    try testing.expectError(error.IndicatorLengthMismatch, candles.addIndicator("bad", bad_values));
}
```

#### manager_test.zig

```zig
const std = @import("std");
const testing = std.testing;
const IndicatorManager = @import("manager.zig").IndicatorManager;
const Candles = @import("../candles.zig").Candles;
const SMA = @import("sma.zig").SMA;

test "IndicatorManager: cache hit" {
    const allocator = testing.allocator;

    var manager = try IndicatorManager.init(allocator);
    defer manager.deinit();

    const candles_data = try createTestCandles(allocator, 100);
    defer allocator.free(candles_data);

    var candles = try Candles.init(
        allocator,
        candles_data,
        TradingPair.init("BTC", "USDT"),
        .m15,
    );
    defer candles.deinit();

    const sma = try SMA.init(allocator, 20);
    defer sma.toIndicator().deinit();

    // 第一次调用 - 缓存未命中
    const result1 = try manager.getOrCalculate("sma_20", sma.toIndicator(), &candles);
    try testing.expectEqual(@as(u64, 0), manager.stats.cache_hits);
    try testing.expectEqual(@as(u64, 1), manager.stats.cache_misses);

    // 第二次调用 - 缓存命中
    const result2 = try manager.getOrCalculate("sma_20", sma.toIndicator(), &candles);
    try testing.expectEqual(@as(u64, 1), manager.stats.cache_hits);
    try testing.expectEqual(@as(u64, 1), manager.stats.cache_misses);

    // 验证结果相同（同一内存地址）
    try testing.expectEqual(result1.ptr, result2.ptr);
}

test "IndicatorManager: cache hit rate" {
    const allocator = testing.allocator;

    var manager = try IndicatorManager.init(allocator);
    defer manager.deinit();

    const candles_data = try createTestCandles(allocator, 100);
    defer allocator.free(candles_data);

    var candles = try Candles.init(
        allocator,
        candles_data,
        TradingPair.init("BTC", "USDT"),
        .m15,
    );
    defer candles.deinit();

    const sma = try SMA.init(allocator, 20);
    defer sma.toIndicator().deinit();

    // 模拟典型使用场景: 1 次计算 + 9 次获取
    _ = try manager.getOrCalculate("sma_20", sma.toIndicator(), &candles);
    for (0..9) |_| {
        _ = try manager.getOrCalculate("sma_20", sma.toIndicator(), &candles);
    }

    // 命中率应该是 90%
    const hit_rate = manager.stats.hitRate();
    try testing.expectApproxEqAbs(@as(f64, 0.9), hit_rate, 0.01);
}

test "IndicatorManager: invalidate cache" {
    const allocator = testing.allocator;

    var manager = try IndicatorManager.init(allocator);
    defer manager.deinit();

    const candles_data = try createTestCandles(allocator, 100);
    defer allocator.free(candles_data);

    var candles = try Candles.init(
        allocator,
        candles_data,
        TradingPair.init("BTC", "USDT"),
        .m15,
    );
    defer candles.deinit();

    const sma = try SMA.init(allocator, 20);
    defer sma.toIndicator().deinit();

    // 计算指标
    _ = try manager.getOrCalculate("sma_20", sma.toIndicator(), &candles);
    try testing.expectEqual(@as(usize, 1), manager.getCacheSize());

    // 失效缓存
    manager.invalidate("sma");
    try testing.expectEqual(@as(usize, 0), manager.getCacheSize());
}

test "IndicatorManager: no memory leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) @panic("Memory leak detected!");
    }
    const allocator = gpa.allocator();

    var manager = try IndicatorManager.init(allocator);
    defer manager.deinit();

    const candles_data = try createTestCandles(allocator, 100);
    defer allocator.free(candles_data);

    var candles = try Candles.init(
        allocator,
        candles_data,
        TradingPair.init("BTC", "USDT"),
        .m15,
    );
    defer candles.deinit();

    const sma = try SMA.init(allocator, 20);
    defer sma.toIndicator().deinit();

    // 多次计算
    for (0..10) |_| {
        _ = try manager.getOrCalculate("sma_20", sma.toIndicator(), &candles);
    }
}
```

#### performance_test.zig

```zig
const std = @import("std");
const testing = std.testing;

test "Performance: cache vs recalculate" {
    const allocator = testing.allocator;

    var manager = try IndicatorManager.init(allocator);
    defer manager.deinit();

    const candles_data = try createTestCandles(allocator, 1000);
    defer allocator.free(candles_data);

    var candles = try Candles.init(
        allocator,
        candles_data,
        TradingPair.init("BTC", "USDT"),
        .m15,
    );
    defer candles.deinit();

    const sma = try SMA.init(allocator, 20);
    defer sma.toIndicator().deinit();

    // 测试缓存未命中时间
    const start1 = std.time.nanoTimestamp();
    _ = try manager.getOrCalculate("sma_20", sma.toIndicator(), &candles);
    const end1 = std.time.nanoTimestamp();
    const miss_time = @as(f64, @floatFromInt(end1 - start1)) / 1_000_000.0;

    // 测试缓存命中时间
    const start2 = std.time.nanoTimestamp();
    for (0..100) |_| {
        _ = try manager.getOrCalculate("sma_20", sma.toIndicator(), &candles);
    }
    const end2 = std.time.nanoTimestamp();
    const hit_time = @as(f64, @floatFromInt(end2 - start2)) / 1_000_000.0 / 100.0;

    std.debug.print("\nCache miss: {d:.3}ms\n", .{miss_time});
    std.debug.print("Cache hit: {d:.3}ms\n", .{hit_time});
    std.debug.print("Speedup: {d:.1}x\n", .{miss_time / hit_time});

    // 缓存命中应该 < 0.1ms
    try testing.expect(hit_time < 0.1);

    // 性能提升应该 > 100x
    try testing.expect(miss_time / hit_time > 100.0);
}

test "Performance: backtest scenario" {
    // 模拟回测场景:
    // - 1000 根 K线
    // - 每根 K线调用 3 个指标（SMA(20), EMA(10), RSI(14)）
    // - 验证缓存命中率 > 90%
    // - 验证总时间 < 100ms
}
```

### 集成测试场景

```bash
# 运行所有测试
$ zig build test --summary all

# 运行性能测试
$ zig test src/strategy/indicators/performance_test.zig

# 内存泄漏检测
$ zig test src/strategy/indicators/manager_test.zig -ftest-filter "no memory leak"
```

---

## 📚 相关文档

### 设计文档
- [ ] `docs/features/strategy/indicators/manager.md` - IndicatorManager 文档
- [ ] `docs/features/strategy/candles.md` - Candles 容器文档
- [ ] `docs/features/strategy/indicators/caching.md` - 缓存策略说明

### 参考资料
- [Story 015]: `STORY_015_TECHNICAL_INDICATORS.md`
- [Story 013]: `STORY_013_ISTRATEGY_INTERFACE.md`

---

## 🔗 依赖关系

### 前置条件
- [x] Story 015: 技术指标库实现完成
- [x] Story 013: IStrategy 接口定义

### 被依赖
- Story 017-019: 内置策略将使用 IndicatorManager
- Story 020: 回测引擎将使用 IndicatorManager

---

## ⚠️ 风险与挑战

### 已识别风险

1. **风险 1**: 缓存键冲突
   - **影响**: 高
   - **缓解措施**:
     - 包含所有关键参数在缓存键中
     - 使用数据哈希避免不同数据集冲突
     - 编写冲突检测测试

2. **风险 2**: 内存占用过大
   - **影响**: 中
   - **缓解措施**:
     - 提供缓存大小限制选项
     - 实现 clear() 方法手动清理
     - 后续可实现 LRU 策略

### 技术挑战

1. **挑战 1**: 数据更新时的缓存失效
   - **解决方案**: 使用数据哈希（首尾时间戳），数据变化时哈希不同

2. **挑战 2**: 指标间的依赖关系
   - **解决方案**: 当前版本不处理复杂依赖，每个指标独立缓存

---

## 📊 进度追踪

### 时间线
- 开始日期: 待定
- 预计完成: 开始后 1 天
- 实际完成: -

### 工作日志
| 日期 | 进展 | 备注 |
|------|------|------|
| - | - | - |

---

## ✅ 验收检查清单

Story 完成前的最终检查：

- [ ] 所有验收标准已满足
- [ ] 所有任务已完成
- [ ] 单元测试通过 (覆盖率 > 85%)
- [ ] 性能测试通过（命中率 > 90%）
- [ ] 集成测试通过
- [ ] 代码已审查
- [ ] 文档已更新
- [ ] 无编译警告
- [ ] 内存泄漏测试通过
- [ ] API 文档注释完整
- [ ] 相关 OVERVIEW 已更新

---

## 💡 未来改进

完成此 Story 后可以考虑的优化方向:

- 优化 1: 实现 LRU 缓存策略，限制内存占用
- 优化 2: 支持持久化缓存（磁盘存储）
- 扩展 1: 支持指标依赖关系管理
- 扩展 2: 提供缓存预热 API（批量计算）
- 扩展 3: 实时监控和可视化缓存状态

---

*Last updated: 2025-12-25*
*Assignee: Claude*
