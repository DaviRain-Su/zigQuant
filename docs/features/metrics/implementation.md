# Prometheus Metrics - 实现细节

> 深入了解内部实现

**最后更新**: 2025-12-28

---

## 架构概述

```
┌─────────────────────────────────────────────────────────┐
│                  MetricsCollector                        │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │    Counters     │  │         Gauges              │  │
│  │  trades_total   │  │  trade_pnl, win_rate, ...   │  │
│  │  orders_total   │  │                             │  │
│  └─────────────────┘  └─────────────────────────────┘  │
│           │                        │                     │
│           ▼                        ▼                     │
│  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │   Histograms    │  │       Exporter              │  │
│  │ order_latency   │  │  Prometheus text format     │  │
│  │ api_latency     │  │                             │  │
│  └─────────────────┘  └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## 内部表示

### MetricsCollector 数据结构

```zig
pub const MetricsCollector = struct {
    allocator: Allocator,

    // Counters - 只增不减的计数器
    trades_total: std.StringHashMap(u64),
    orders_total: std.StringHashMap(u64),
    api_requests_total: std.StringHashMap(u64),
    alerts_total: std.StringHashMap(u64),

    // Gauges - 可增可减的数值
    trade_pnl: std.StringHashMap(f64),
    win_rate: std.StringHashMap(f64),
    sharpe_ratio: std.StringHashMap(f64),
    position_size: std.StringHashMap(f64),
    position_pnl: std.StringHashMap(f64),
    max_drawdown: f64,
    memory_bytes: std.StringHashMap(u64),
    uptime_start: i64,

    // Histograms - 分布统计
    order_latency: Histogram,
    api_latency: std.StringHashMap(Histogram),

    // 互斥锁 (线程安全)
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .trades_total = std.StringHashMap(u64).init(allocator),
            .orders_total = std.StringHashMap(u64).init(allocator),
            .api_requests_total = std.StringHashMap(u64).init(allocator),
            .alerts_total = std.StringHashMap(u64).init(allocator),
            .trade_pnl = std.StringHashMap(f64).init(allocator),
            .win_rate = std.StringHashMap(f64).init(allocator),
            .sharpe_ratio = std.StringHashMap(f64).init(allocator),
            .position_size = std.StringHashMap(f64).init(allocator),
            .position_pnl = std.StringHashMap(f64).init(allocator),
            .max_drawdown = 0,
            .memory_bytes = std.StringHashMap(u64).init(allocator),
            .uptime_start = std.time.timestamp(),
            .order_latency = Histogram.init(allocator, &default_buckets),
            .api_latency = std.StringHashMap(Histogram).init(allocator),
            .mutex = .{},
        };
    }
};

const default_buckets = [_]f64{ 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0 };
```

### Histogram 数据结构

```zig
pub const Histogram = struct {
    allocator: Allocator,
    buckets: []const f64,
    counts: []u64,
    sum: f64,
    count: u64,

    const Self = @This();

    pub fn init(allocator: Allocator, buckets: []const f64) Self {
        // counts 数组比 buckets 多一个 (用于 +Inf)
        const counts = allocator.alloc(u64, buckets.len + 1) catch unreachable;
        @memset(counts, 0);

        return .{
            .allocator = allocator,
            .buckets = buckets,
            .counts = counts,
            .sum = 0,
            .count = 0,
        };
    }

    pub fn observe(self: *Self, value: f64) void {
        self.sum += value;
        self.count += 1;

        // 累积直方图: 每个 bucket 包含所有 <= 该值的观测
        for (self.buckets, 0..) |bucket, i| {
            if (value <= bucket) {
                self.counts[i] += 1;
            }
        }
        // +Inf bucket 总是递增
        self.counts[self.buckets.len] += 1;
    }

    pub fn reset(self: *Self) void {
        @memset(self.counts, 0);
        self.sum = 0;
        self.count = 0;
    }
};
```

---

## 核心算法

### Counter 递增

```zig
pub fn incCounter(self: *Self, map: *std.StringHashMap(u64), key: []const u8) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const entry = map.getOrPut(key) catch return;
    if (entry.found_existing) {
        entry.value_ptr.* += 1;
    } else {
        entry.value_ptr.* = 1;
    }
}

pub fn incTrade(self: *Self, strategy: []const u8, pair: []const u8, side: []const u8) void {
    const key = std.fmt.allocPrint(self.allocator, "{s},{s},{s}", .{strategy, pair, side}) catch return;
    defer self.allocator.free(key);

    self.incCounter(&self.trades_total, key);
}
```

**复杂度**: O(1) 平均情况
**说明**: 使用互斥锁确保线程安全

### Gauge 设置

```zig
pub fn setGauge(self: *Self, map: *std.StringHashMap(f64), key: []const u8, value: f64) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    map.put(key, value) catch {};
}

pub fn setWinRate(self: *Self, strategy: []const u8, rate: f64) void {
    self.setGauge(&self.win_rate, strategy, rate);
}
```

### Histogram 观测

```zig
pub fn observeHistogram(self: *Self, histogram: *Histogram, value: f64) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    histogram.observe(value);
}

pub fn observeApiLatency(self: *Self, method: []const u8, path: []const u8, latency: f64) void {
    const key = std.fmt.allocPrint(self.allocator, "{s},{s}", .{method, path}) catch return;

    self.mutex.lock();
    defer self.mutex.unlock();

    const entry = self.api_latency.getOrPut(key) catch return;
    if (!entry.found_existing) {
        entry.value_ptr.* = Histogram.init(self.allocator, &default_buckets);
    }
    entry.value_ptr.observe(latency);
}
```

**复杂度**: O(b) 其中 b 是 bucket 数量
**说明**: 需要遍历所有 bucket 更新计数

---

## Prometheus 格式导出

### 导出算法

```zig
pub fn export(self: *Self, allocator: Allocator) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    const writer = output.writer();

    self.mutex.lock();
    defer self.mutex.unlock();

    // 1. 导出 Counters
    try self.exportCounter(writer, "zigquant_trades_total", "Total number of trades", &self.trades_total);
    try self.exportCounter(writer, "zigquant_orders_total", "Total number of orders", &self.orders_total);
    try self.exportCounter(writer, "zigquant_api_requests_total", "Total API requests", &self.api_requests_total);

    // 2. 导出 Gauges
    try self.exportGauge(writer, "zigquant_win_rate", "Strategy win rate", &self.win_rate);
    try self.exportGauge(writer, "zigquant_trade_pnl", "Trade PnL", &self.trade_pnl);
    try self.exportSimpleGauge(writer, "zigquant_max_drawdown", "Maximum drawdown", self.max_drawdown);

    // 3. 导出 Histograms
    try self.exportHistogram(writer, "zigquant_order_latency_seconds", "Order latency", &self.order_latency);

    // 4. 导出系统指标
    const uptime = std.time.timestamp() - self.uptime_start;
    try writer.print("# HELP zigquant_uptime_seconds Uptime in seconds\n", .{});
    try writer.print("# TYPE zigquant_uptime_seconds counter\n", .{});
    try writer.print("zigquant_uptime_seconds {d}\n\n", .{uptime});

    return output.toOwnedSlice();
}

fn exportCounter(self: *Self, writer: anytype, name: []const u8, help: []const u8, map: *std.StringHashMap(u64)) !void {
    try writer.print("# HELP {s} {s}\n", .{name, help});
    try writer.print("# TYPE {s} counter\n", .{name});

    var it = map.iterator();
    while (it.next()) |entry| {
        const labels = parseLabels(entry.key_ptr.*);
        try writer.print("{s}{{{s}}} {d}\n", .{name, labels, entry.value_ptr.*});
    }
    try writer.writeByte('\n');
}

fn exportHistogram(self: *Self, writer: anytype, name: []const u8, help: []const u8, histogram: *Histogram) !void {
    try writer.print("# HELP {s} {s}\n", .{name, help});
    try writer.print("# TYPE {s} histogram\n", .{name});

    // 导出累积 buckets
    var cumulative: u64 = 0;
    for (histogram.buckets, 0..) |bucket, i| {
        cumulative += histogram.counts[i];
        try writer.print("{s}_bucket{{le=\"{d}\"}} {d}\n", .{name, bucket, cumulative});
    }
    try writer.print("{s}_bucket{{le=\"+Inf\"}} {d}\n", .{name, histogram.count});
    try writer.print("{s}_sum {d}\n", .{name, histogram.sum});
    try writer.print("{s}_count {d}\n\n", .{name, histogram.count});
}
```

---

## 性能优化

### 标签键缓存

为避免频繁的字符串拼接，缓存常用标签组合：

```zig
const LabelCache = struct {
    cache: std.StringHashMap([]const u8),
    allocator: Allocator,

    pub fn getOrCreate(self: *LabelCache, parts: []const []const u8) []const u8 {
        const key = std.mem.join(self.allocator, ",", parts) catch return "";
        defer self.allocator.free(key);

        if (self.cache.get(key)) |cached| {
            return cached;
        }

        const stored = self.allocator.dupe(u8, key) catch return "";
        self.cache.put(stored, stored) catch {};
        return stored;
    }
};
```

### 批量导出

使用预分配缓冲区减少分配：

```zig
const EXPORT_BUFFER_SIZE = 64 * 1024;  // 64KB

pub fn exportToBuffer(self: *Self, buffer: []u8) !usize {
    var fbs = std.io.fixedBufferStream(buffer);
    const writer = fbs.writer();

    // 直接写入固定缓冲区
    try self.exportAll(writer);

    return fbs.pos;
}
```

### 无锁读取 (规划中)

使用读写锁允许并发读取：

```zig
// 规划中的优化
rw_lock: std.Thread.RwLock,

pub fn export(self: *Self, ...) ![]const u8 {
    self.rw_lock.lockShared();  // 共享读锁
    defer self.rw_lock.unlockShared();
    // ...
}

pub fn incCounter(self: *Self, ...) void {
    self.rw_lock.lock();  // 独占写锁
    defer self.rw_lock.unlock();
    // ...
}
```

---

## 内存管理

### 指标生命周期

```zig
pub fn deinit(self: *Self) void {
    // 释放 HashMap 中的所有 key
    var it = self.trades_total.keyIterator();
    while (it.next()) |key| {
        self.allocator.free(key.*);
    }
    self.trades_total.deinit();

    // 释放 Histograms
    self.order_latency.deinit();

    var hist_it = self.api_latency.iterator();
    while (hist_it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    self.api_latency.deinit();

    // ... 释放其他资源
}
```

### 内存估算

```
每个 Counter:
  - Key (平均 32 bytes) + Value (8 bytes) = ~40 bytes

每个 Histogram (11 buckets):
  - Buckets array: 11 * 8 = 88 bytes
  - Counts array: 12 * 8 = 96 bytes
  - Sum + Count: 16 bytes
  = ~200 bytes

1000 个指标估算:
  - 500 Counters: 20KB
  - 300 Gauges: 15KB
  - 200 Histograms: 40KB
  = ~75KB
```

---

## 边界情况

### 高基数标签

限制标签组合数量防止内存溢出：

```zig
const MAX_LABEL_COMBINATIONS = 10000;

pub fn incCounter(self: *Self, map: *std.StringHashMap(u64), key: []const u8) void {
    if (map.count() >= MAX_LABEL_COMBINATIONS) {
        std.log.warn("Max label combinations reached, dropping metric", .{});
        return;
    }
    // ...
}
```

### 溢出处理

Counter 使用 u64 最大值约 1.8e19，实际使用中不太可能溢出：

```zig
pub fn incCounter(self: *Self, map: *std.StringHashMap(u64), key: []const u8) void {
    const entry = map.getOrPut(key) catch return;
    if (entry.found_existing) {
        // 溢出检查 (理论上)
        entry.value_ptr.* = @addWithOverflow(entry.value_ptr.*, 1)[0];
    } else {
        entry.value_ptr.* = 1;
    }
}
```

---

## 文件结构

```
src/api/metrics/
├── mod.zig              # 模块导出
├── collector.zig        # MetricsCollector 实现
├── histogram.zig        # Histogram 实现
├── exporter.zig         # Prometheus 格式导出
└── types.zig            # 类型定义
```

---

*完整实现请参考: `src/api/metrics/`*
