# ZigQuant 性能优化指南

> 低延迟、高吞吐量的系统优化策略

---

## 🎯 性能目标

```
┌─────────────────────────────────────────────────────────┐
│                Performance Targets                       │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  Metric                Target          Current           │
│  ─────────────────────────────────────────────           │
│  Order Latency (P99)    < 10ms          ?                │
│  WebSocket Throughput   > 100K msg/s    ?                │
│  Backtest Speed         > 100K ticks/s  ?                │
│  Memory Usage           < 500MB         ?                │
│  CPU Usage (1 core)     < 50%           ?                │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

---

## 1. 编译优化

### 1.1 编译选项

```zig
// build.zig

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zigquant",
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
    });

    // ReleaseFast 模式配置
    if (optimize == .ReleaseFast) {
        // 启用 LTO (Link Time Optimization)
        exe.want_lto = true;

        // 启用更激进的优化
        exe.strip = true;  // 移除调试符号

        // 使用特定 CPU 特性
        exe.code_model = .small;
        exe.link_libc = false;  // 减少依赖
    }

    // ReleaseSafe 模式 (推荐生产环境)
    if (optimize == .ReleaseSafe) {
        exe.want_lto = true;

        // 保留关键安全检查
        // - 数组越界检查
        // - 整数溢出检查
        // - 未定义行为检查
    }
}
```

### 1.2 CPU 特性优化

```bash
# 针对特定 CPU 架构编译
zig build -Dtarget=native -Doptimize=ReleaseFast

# 使用 AVX2 指令集
zig build -Dcpu=x86_64-v3 -Doptimize=ReleaseFast

# 查看生成的汇编代码
zig build-exe src/main.zig -femit-asm=output.s -O ReleaseFast
```

---

## 2. 内存优化

### 2.1 Arena Allocator 使用

```zig
// src/core/memory.zig

pub const MemoryPool = struct {
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    pub fn init(backing_allocator: std.mem.Allocator) MemoryPool {
        return .{
            .arena = std.heap.ArenaAllocator.init(backing_allocator),
            .allocator = undefined,
        };
    }

    pub fn deinit(self: *MemoryPool) void {
        self.arena.deinit();
    }

    pub fn getAllocator(self: *MemoryPool) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// 重置 arena (释放所有分配)
    pub fn reset(self: *MemoryPool) void {
        _ = self.arena.reset(.retain_capacity);
    }
};

// 使用示例：每个交易周期使用独立的 arena
pub const TradingCycle = struct {
    pool: MemoryPool,

    pub fn init(allocator: std.mem.Allocator) TradingCycle {
        return .{
            .pool = MemoryPool.init(allocator),
        };
    }

    pub fn tick(self: *TradingCycle) void {
        // 使用 arena allocator 处理本周期的临时数据
        const cycle_allocator = self.pool.getAllocator();

        // 处理订单簿更新
        const orderbook = Orderbook.init(cycle_allocator, pair);
        // ... 处理逻辑

        // 周期结束时重置，释放所有临时分配
        self.pool.reset();
    }
};
```

### 2.2 对象池模式

```zig
// src/core/object_pool.zig

pub fn ObjectPool(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        pool: std.ArrayList(*T),
        in_use: std.AutoHashMap(*T, void),
        max_size: usize,

        pub fn init(allocator: std.mem.Allocator, initial_size: usize, max_size: usize) !Self {
            var pool = std.ArrayList(*T).init(allocator);
            try pool.ensureTotalCapacity(initial_size);

            // 预分配对象
            var i: usize = 0;
            while (i < initial_size) : (i += 1) {
                const obj = try allocator.create(T);
                try pool.append(obj);
            }

            return .{
                .allocator = allocator,
                .pool = pool,
                .in_use = std.AutoHashMap(*T, void).init(allocator),
                .max_size = max_size,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.pool.items) |obj| {
                self.allocator.destroy(obj);
            }
            self.pool.deinit();
            self.in_use.deinit();
        }

        pub fn acquire(self: *Self) !*T {
            if (self.pool.items.len > 0) {
                const obj = self.pool.pop();
                try self.in_use.put(obj, {});
                return obj;
            }

            // 池已空，创建新对象
            if (self.in_use.count() < self.max_size) {
                const obj = try self.allocator.create(T);
                try self.in_use.put(obj, {});
                return obj;
            }

            return error.PoolExhausted;
        }

        pub fn release(self: *Self, obj: *T) void {
            _ = self.in_use.remove(obj);

            // 重置对象状态
            if (@hasDecl(T, "reset")) {
                obj.reset();
            }

            self.pool.append(obj) catch {
                // 池已满，销毁对象
                self.allocator.destroy(obj);
            };
        }
    };
}

// 使用示例
const OrderPool = ObjectPool(Order);

var order_pool = try OrderPool.init(allocator, 100, 1000);
defer order_pool.deinit();

// 获取对象
const order = try order_pool.acquire();
// 使用 order...

// 归还对象
order_pool.release(order);
```

### 2.3 内存使用监控

```zig
// src/performance/memory_profiler.zig

pub const MemoryProfiler = struct {
    allocator: std.mem.Allocator,
    samples: std.ArrayList(MemorySample),
    start_rss: usize,

    pub const MemorySample = struct {
        timestamp: i64,
        rss: usize,  // Resident Set Size
        heap: usize,
        stack: usize,
    };

    pub fn init(allocator: std.mem.Allocator) !MemoryProfiler {
        return .{
            .allocator = allocator,
            .samples = std.ArrayList(MemorySample).init(allocator),
            .start_rss = try getCurrentRSS(),
        };
    }

    pub fn sample(self: *MemoryProfiler) !void {
        try self.samples.append(.{
            .timestamp = std.time.milliTimestamp(),
            .rss = try getCurrentRSS(),
            .heap = getHeapUsage(),
            .stack = getStackUsage(),
        });
    }

    fn getCurrentRSS() !usize {
        if (std.builtin.os.tag == .linux) {
            const file = try std.fs.openFileAbsolute("/proc/self/statm", .{});
            defer file.close();

            var buf: [256]u8 = undefined;
            const bytes_read = try file.readAll(&buf);
            const content = buf[0..bytes_read];

            var iter = std.mem.splitScalar(u8, content, ' ');
            _ = iter.next(); // total
            const rss_pages = iter.next() orelse return 0;

            const pages = try std.fmt.parseInt(usize, rss_pages, 10);
            return pages * std.mem.page_size;
        }

        return 0;
    }

    pub fn report(self: *MemoryProfiler) void {
        if (self.samples.items.len == 0) return;

        const latest = self.samples.getLast();
        const peak = blk: {
            var max = self.samples.items[0];
            for (self.samples.items) |sample| {
                if (sample.rss > max.rss) max = sample;
            }
            break :blk max;
        };

        std.debug.print("Memory Usage:\n", .{});
        std.debug.print("  Current RSS: {d} MB\n", .{latest.rss / 1024 / 1024});
        std.debug.print("  Peak RSS: {d} MB\n", .{peak.rss / 1024 / 1024});
        std.debug.print("  Delta: +{d} MB\n", .{(latest.rss - self.start_rss) / 1024 / 1024});
    }
};
```

---

## 3. 数据结构优化

### 3.1 高性能订单簿

```zig
// src/market/fast_orderbook.zig

pub const FastOrderbook = struct {
    // 使用固定大小数组 + 红黑树混合结构
    bids_top: [100]PriceLevel,  // 前100档使用数组
    asks_top: [100]PriceLevel,
    bids_deep: RBTree(PriceLevel),  // 深度档位使用树
    asks_deep: RBTree(PriceLevel),

    bids_count: usize,
    asks_count: usize,

    pub fn update(self: *FastOrderbook, level: PriceLevel, side: Side) !void {
        const top_array = if (side == .bid) &self.bids_top else &self.asks_top;
        const count = if (side == .bid) &self.bids_count else &self.asks_count;

        if (count.* < 100) {
            // 直接插入数组
            top_array[count.*] = level;
            count.* += 1;

            // 保持排序
            self.sortTopLevels(side);
        } else {
            // 插入树
            const tree = if (side == .bid) &self.bids_deep else &self.asks_deep;
            try tree.insert(level);
        }
    }

    pub fn getBestBid(self: *FastOrderbook) ?PriceLevel {
        if (self.bids_count > 0) {
            return self.bids_top[0];
        }
        return null;
    }

    fn sortTopLevels(self: *FastOrderbook, side: Side) void {
        const array = if (side == .bid) &self.bids_top else &self.asks_top;
        const count = if (side == .bid) self.bids_count else self.asks_count;

        // 使用插入排序，适合小数组
        var i: usize = 1;
        while (i < count) : (i += 1) {
            const key = array[i];
            var j: usize = i;
            while (j > 0 and shouldSwap(array[j - 1], key, side)) : (j -= 1) {
                array[j] = array[j - 1];
            }
            array[j] = key;
        }
    }
};
```

### 3.2 缓存友好的数据布局

```zig
// src/core/data_layout.zig

// 不好的设计：指针追逐
pub const OrderBad = struct {
    id: []const u8,
    pair: *TradingPair,  // 指针
    price: *Decimal,     // 指针
    amount: *Decimal,    // 指针
    // ... 更多字段
};

// 好的设计：数据局部性
pub const OrderGood = struct {
    // 常用字段放在前面
    price: Decimal,      // 内联
    amount: Decimal,     // 内联
    side: Side,
    status: OrderStatus,

    // 不常用字段放后面
    id: [32]u8,          // 固定大小
    pair: TradingPair,   // 内联
    created_at: i64,
    // ...
};

// 结构体数组优于指针数组
pub const OrderBook = struct {
    // 不好：指针数组
    orders_bad: std.ArrayList(*Order),

    // 好：值数组
    orders_good: std.ArrayList(Order),
};
```

---

## 4. 并发优化

### 4.1 无锁数据结构

```zig
// src/core/lock_free_queue.zig

pub fn LockFreeQueue(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = struct {
            data: T,
            next: std.atomic.Value(?*Node),
        };

        head: std.atomic.Value(*Node),
        tail: std.atomic.Value(*Node),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !Self {
            const dummy = try allocator.create(Node);
            dummy.* = .{
                .data = undefined,
                .next = std.atomic.Value(?*Node).init(null),
            };

            return .{
                .head = std.atomic.Value(*Node).init(dummy),
                .tail = std.atomic.Value(*Node).init(dummy),
                .allocator = allocator,
            };
        }

        pub fn enqueue(self: *Self, data: T) !void {
            const node = try self.allocator.create(Node);
            node.* = .{
                .data = data,
                .next = std.atomic.Value(?*Node).init(null),
            };

            while (true) {
                const tail = self.tail.load(.acquire);
                const next = tail.next.load(.acquire);

                if (tail == self.tail.load(.acquire)) {
                    if (next == null) {
                        if (tail.next.cmpxchgWeak(
                            null,
                            node,
                            .release,
                            .acquire,
                        ) == null) {
                            _ = self.tail.cmpxchgWeak(tail, node, .release, .acquire);
                            return;
                        }
                    } else {
                        _ = self.tail.cmpxchgWeak(tail, next.?, .release, .acquire);
                    }
                }
            }
        }

        pub fn dequeue(self: *Self) ?T {
            while (true) {
                const head = self.head.load(.acquire);
                const tail = self.tail.load(.acquire);
                const next = head.next.load(.acquire);

                if (head == self.head.load(.acquire)) {
                    if (head == tail) {
                        if (next == null) {
                            return null;  // 队列为空
                        }
                        _ = self.tail.cmpxchgWeak(tail, next.?, .release, .acquire);
                    } else {
                        const data = next.?.data;
                        if (self.head.cmpxchgWeak(head, next.?, .release, .acquire) == head) {
                            self.allocator.destroy(head);
                            return data;
                        }
                    }
                }
            }
        }
    };
}
```

### 4.2 线程池

```zig
// src/core/thread_pool.zig

pub const ThreadPool = struct {
    allocator: std.mem.Allocator,
    threads: []std.Thread,
    queue: LockFreeQueue(Task),
    running: std.atomic.Value(bool),

    pub const Task = struct {
        func: *const fn (*anyopaque) void,
        data: *anyopaque,
    };

    pub fn init(allocator: std.mem.Allocator, num_threads: u32) !ThreadPool {
        var threads = try allocator.alloc(std.Thread, num_threads);
        const queue = try LockFreeQueue(Task).init(allocator);

        var pool = ThreadPool{
            .allocator = allocator,
            .threads = threads,
            .queue = queue,
            .running = std.atomic.Value(bool).init(true),
        };

        // 启动工作线程
        for (threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, worker, .{&pool});
        }

        return pool;
    }

    fn worker(pool: *ThreadPool) void {
        while (pool.running.load(.acquire)) {
            if (pool.queue.dequeue()) |task| {
                task.func(task.data);
            } else {
                std.time.sleep(1 * std.time.ns_per_ms);
            }
        }
    }

    pub fn submit(self: *ThreadPool, func: *const fn (*anyopaque) void, data: *anyopaque) !void {
        try self.queue.enqueue(.{ .func = func, .data = data });
    }

    pub fn shutdown(self: *ThreadPool) void {
        self.running.store(false, .release);

        for (self.threads) |thread| {
            thread.join();
        }
    }
};
```

---

## 5. I/O 优化

### 5.1 批量处理

```zig
// src/network/batch_processor.zig

pub const BatchProcessor = struct {
    buffer: std.ArrayList(Message),
    flush_size: usize,
    flush_interval: i64,
    last_flush: i64,

    pub fn init(allocator: std.mem.Allocator, flush_size: usize, flush_interval_ms: i64) BatchProcessor {
        return .{
            .buffer = std.ArrayList(Message).init(allocator),
            .flush_size = flush_size,
            .flush_interval = flush_interval_ms * std.time.ns_per_ms,
            .last_flush = std.time.nanoTimestamp(),
        };
    }

    pub fn add(self: *BatchProcessor, msg: Message) !void {
        try self.buffer.append(msg);

        const now = std.time.nanoTimestamp();

        // 达到批量大小或超时时刷新
        if (self.buffer.items.len >= self.flush_size or
            now - self.last_flush >= self.flush_interval)
        {
            try self.flush();
        }
    }

    fn flush(self: *BatchProcessor) !void {
        if (self.buffer.items.len == 0) return;

        // 批量发送
        try sendBatch(self.buffer.items);

        self.buffer.clearRetainingCapacity();
        self.last_flush = std.time.nanoTimestamp();
    }
};
```

### 5.2 零拷贝

```zig
// src/network/zero_copy.zig

pub const ZeroCopyBuffer = struct {
    mmap_region: []align(std.mem.page_size) u8,
    read_offset: usize,
    write_offset: usize,

    pub fn init(size: usize) !ZeroCopyBuffer {
        const mmap_region = try std.os.mmap(
            null,
            size,
            std.os.PROT.READ | std.os.PROT.WRITE,
            std.os.MAP.PRIVATE | std.os.MAP.ANONYMOUS,
            -1,
            0,
        );

        return .{
            .mmap_region = mmap_region,
            .read_offset = 0,
            .write_offset = 0,
        };
    }

    pub fn deinit(self: *ZeroCopyBuffer) void {
        std.os.munmap(self.mmap_region);
    }

    pub fn getWriteSlice(self: *ZeroCopyBuffer) []u8 {
        return self.mmap_region[self.write_offset..];
    }

    pub fn advance(self: *ZeroCopyBuffer, bytes: usize) void {
        self.write_offset += bytes;
    }
};
```

---

## 6. 性能测量

### 6.1 Profiling 工具

```zig
// src/performance/profiler.zig

pub const Profiler = struct {
    samples: std.StringHashMap(Sample),
    allocator: std.mem.Allocator,

    pub const Sample = struct {
        count: u64,
        total_ns: u64,
        min_ns: u64,
        max_ns: u64,

        pub fn record(self: *Sample, duration_ns: u64) void {
            self.count += 1;
            self.total_ns += duration_ns;
            self.min_ns = @min(self.min_ns, duration_ns);
            self.max_ns = @max(self.max_ns, duration_ns);
        }

        pub fn avg(self: Sample) u64 {
            if (self.count == 0) return 0;
            return self.total_ns / self.count;
        }
    };

    pub fn init(allocator: std.mem.Allocator) Profiler {
        return .{
            .samples = std.StringHashMap(Sample).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn start(self: *Profiler, name: []const u8) i64 {
        return std.time.nanoTimestamp();
    }

    pub fn end(self: *Profiler, name: []const u8, start_time: i64) void {
        const duration = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));

        const entry = self.samples.getPtr(name) orelse blk: {
            self.samples.put(name, Sample{
                .count = 0,
                .total_ns = 0,
                .min_ns = std.math.maxInt(u64),
                .max_ns = 0,
            }) catch return;
            break :blk self.samples.getPtr(name).?;
        };

        entry.record(duration);
    }

    pub fn report(self: *Profiler) void {
        std.debug.print("\nPerformance Report:\n", .{});
        std.debug.print("{s:<30} {s:>10} {s:>10} {s:>10} {s:>10}\n", .{
            "Operation",
            "Count",
            "Avg (µs)",
            "Min (µs)",
            "Max (µs)",
        });
        std.debug.print("{s}\n", .{"-" ** 80});

        var iter = self.samples.iterator();
        while (iter.next()) |entry| {
            const sample = entry.value_ptr.*;
            std.debug.print("{s:<30} {d:>10} {d:>10} {d:>10} {d:>10}\n", .{
                entry.key_ptr.*,
                sample.count,
                sample.avg() / 1000,
                sample.min_ns / 1000,
                sample.max_ns / 1000,
            });
        }
    }
};

// 使用示例
var profiler = Profiler.init(allocator);

const start = profiler.start("order_submit");
try submitOrder(request);
profiler.end("order_submit", start);

// 程序结束时
profiler.report();
```

### 6.2 延迟直方图

```zig
// src/performance/latency_histogram.zig

pub const LatencyHistogram = struct {
    buckets: [20]u64,  // 对数刻度桶
    count: u64,
    sum: u64,

    const BUCKET_BOUNDS = [_]u64{
        1_000,      // 1µs
        2_000,      // 2µs
        5_000,      // 5µs
        10_000,     // 10µs
        20_000,     // 20µs
        50_000,     // 50µs
        100_000,    // 100µs
        200_000,    // 200µs
        500_000,    // 500µs
        1_000_000,  // 1ms
        2_000_000,  // 2ms
        5_000_000,  // 5ms
        10_000_000, // 10ms
        // ...
    };

    pub fn init() LatencyHistogram {
        return .{
            .buckets = [_]u64{0} ** 20,
            .count = 0,
            .sum = 0,
        };
    }

    pub fn record(self: *LatencyHistogram, latency_ns: u64) void {
        self.count += 1;
        self.sum += latency_ns;

        for (BUCKET_BOUNDS, 0..) |bound, i| {
            if (latency_ns < bound) {
                self.buckets[i] += 1;
                return;
            }
        }
        self.buckets[self.buckets.len - 1] += 1;
    }

    pub fn percentile(self: *LatencyHistogram, p: f64) u64 {
        const target = @as(u64, @intFromFloat(@as(f64, @floatFromInt(self.count)) * p));
        var cumulative: u64 = 0;

        for (BUCKET_BOUNDS, 0..) |bound, i| {
            cumulative += self.buckets[i];
            if (cumulative >= target) {
                return bound;
            }
        }

        return BUCKET_BOUNDS[BUCKET_BOUNDS.len - 1];
    }

    pub fn report(self: *LatencyHistogram) void {
        std.debug.print("Latency Distribution:\n", .{});
        std.debug.print("  Count: {d}\n", .{self.count});
        std.debug.print("  Mean: {d} µs\n", .{self.sum / self.count / 1000});
        std.debug.print("  P50: {d} µs\n", .{self.percentile(0.50) / 1000});
        std.debug.print("  P95: {d} µs\n", .{self.percentile(0.95) / 1000});
        std.debug.print("  P99: {d} µs\n", .{self.percentile(0.99) / 1000});
        std.debug.print("  P99.9: {d} µs\n", .{self.percentile(0.999) / 1000});
    }
};
```

---

## 7. 性能调优检查清单

### 编译优化
- [ ] 使用 ReleaseFast 或 ReleaseSafe
- [ ] 启用 LTO
- [ ] 针对目标 CPU 优化
- [ ] 移除未使用代码

### 内存优化
- [ ] 使用 Arena Allocator 处理临时数据
- [ ] 实现对象池减少分配
- [ ] 避免不必要的内存拷贝
- [ ] 监控内存泄漏

### 数据结构
- [ ] 选择合适的数据结构
- [ ] 保持缓存友好的内存布局
- [ ] 使用固定大小数组替代动态分配
- [ ] 预分配容量避免动态扩容

### 并发
- [ ] 使用无锁数据结构
- [ ] 避免锁竞争
- [ ] 合理使用线程池
- [ ] 减少同步开销

### I/O
- [ ] 批量处理减少系统调用
- [ ] 使用异步 I/O
- [ ] 实现零拷贝传输
- [ ] 复用连接

### 测量
- [ ] 持续测量关键路径延迟
- [ ] 记录性能基线
- [ ] 监控性能退化
- [ ] 定期进行性能测试

---

*Last updated: 2025-01*
