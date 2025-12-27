# Vectorized Backtest 实现细节

**版本**: v0.6.0
**状态**: 📋 待开始

---

## 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                  VectorizedBacktester                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ MmapLoader  │  │ SimdIndic.  │  │ BatchSignal │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         ↓                ↓                ↓                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │      Candle[] → Indicator[] → Signal[] → Trade[]    │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## SIMD 优化技术

### Zig Vector 类型

```zig
// 4-wide double precision vector
const Vec4f64 = @Vector(4, f64);

// 8-wide single precision vector
const Vec8f32 = @Vector(8, f32);
```

### SMA SIMD 实现

```zig
pub fn computeSMA_SIMD(prices: []const f64, period: usize, result: []f64) void {
    const Vec4 = @Vector(4, f64);

    // 处理前 period-1 个值 (无法计算 SMA)
    for (0..period - 1) |i| {
        result[i] = std.math.nan(f64);
    }

    // SIMD 批量处理
    var i: usize = period - 1;
    while (i + 4 <= prices.len) : (i += 4) {
        var sums: Vec4 = @splat(0.0);

        // 累加窗口内的值
        var j: usize = 0;
        while (j < period) : (j += 1) {
            const idx = i - period + 1 + j;
            sums += Vec4{
                prices[idx],
                prices[idx + 1],
                prices[idx + 2],
                prices[idx + 3],
            };
        }

        // 计算平均值
        const divisor: Vec4 = @splat(@as(f64, @floatFromInt(period)));
        const avg = sums / divisor;

        // 存储结果
        result[i..][0..4].* = avg;
    }

    // 处理剩余元素 (标量)
    while (i < prices.len) : (i += 1) {
        var sum: f64 = 0;
        for (0..period) |j| {
            sum += prices[i - period + 1 + j];
        }
        result[i] = sum / @as(f64, @floatFromInt(period));
    }
}
```

### RSI SIMD 实现

```zig
pub fn computeRSI_SIMD(prices: []const f64, period: usize, result: []f64) void {
    const Vec4 = @Vector(4, f64);

    // 1. 计算价格变化 (SIMD)
    var changes: []f64 = allocator.alloc(f64, prices.len - 1);
    defer allocator.free(changes);

    var i: usize = 0;
    while (i + 4 <= changes.len) : (i += 4) {
        const curr: Vec4 = prices[i + 1 ..][0..4].*;
        const prev: Vec4 = prices[i..][0..4].*;
        changes[i..][0..4].* = curr - prev;
    }

    // 2. 分离涨跌 (SIMD)
    var gains: []f64 = allocator.alloc(f64, changes.len);
    var losses: []f64 = allocator.alloc(f64, changes.len);

    i = 0;
    while (i + 4 <= changes.len) : (i += 4) {
        const change: Vec4 = changes[i..][0..4].*;
        const zero: Vec4 = @splat(0.0);

        gains[i..][0..4].* = @max(change, zero);
        losses[i..][0..4].* = @abs(@min(change, zero));
    }

    // 3. 计算平均涨跌幅 (滑动窗口)
    // 4. 计算 RSI = 100 - (100 / (1 + RS))
}
```

---

## 内存映射加载

### mmap 实现

```zig
pub const MmapDataLoader = struct {
    pub fn load(path: []const u8) !MappedData {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        const size = stat.size;

        // 内存映射
        const mapped = try std.os.mmap(
            null,
            size,
            std.os.PROT.READ,
            std.os.MAP.PRIVATE,
            file.handle,
            0,
        );

        return .{
            .data = mapped,
            .size = size,
        };
    }

    pub fn unload(self: *MappedData) void {
        std.os.munmap(self.data);
    }
};
```

### CSV 解析

```zig
fn parseCandles(data: []const u8) ![]Candle {
    var candles = std.ArrayList(Candle).init(allocator);

    var lines = std.mem.splitScalar(u8, data, '\n');
    _ = lines.next(); // 跳过标题行

    while (lines.next()) |line| {
        if (line.len == 0) continue;

        var fields = std.mem.splitScalar(u8, line, ',');
        const timestamp = try std.fmt.parseInt(i64, fields.next().?, 10);
        const open = try std.fmt.parseFloat(f64, fields.next().?);
        const high = try std.fmt.parseFloat(f64, fields.next().?);
        const low = try std.fmt.parseFloat(f64, fields.next().?);
        const close = try std.fmt.parseFloat(f64, fields.next().?);
        const volume = try std.fmt.parseFloat(f64, fields.next().?);

        try candles.append(.{
            .timestamp = Timestamp.fromMillis(timestamp),
            .open = open,
            .high = high,
            .low = low,
            .close = close,
            .volume = volume,
        });
    }

    return candles.toOwnedSlice();
}
```

---

## 批量信号生成

```zig
pub const BatchSignalGenerator = struct {
    /// 批量生成 MA 交叉信号
    pub fn generateMACrossSignals(
        fast_ma: []const f64,
        slow_ma: []const f64,
        result: []Signal,
    ) void {
        var prev_above = fast_ma[0] > slow_ma[0];

        for (1..fast_ma.len) |i| {
            const curr_above = fast_ma[i] > slow_ma[i];

            if (curr_above and !prev_above) {
                result[i] = .{ .direction = .long, .strength = 1.0 };
            } else if (!curr_above and prev_above) {
                result[i] = .{ .direction = .short, .strength = 1.0 };
            } else {
                result[i] = .{ .direction = .neutral, .strength = 0.0 };
            }

            prev_above = curr_above;
        }
    }
};
```

---

## 批量订单模拟

```zig
pub const BatchOrderSimulator = struct {
    pub fn simulate(
        candles: []const Candle,
        signals: []const Signal,
        config: Config,
    ) SimulationResult {
        var capital = config.initial_capital;
        var position: f64 = 0;
        var trades = std.ArrayList(Trade).init(allocator);

        for (candles, signals, 0..) |candle, signal, i| {
            switch (signal.direction) {
                .long => {
                    if (position <= 0) {
                        const price = candle.close * (1 + config.slippage);
                        const size = capital / price;
                        position = size;
                        capital = 0;

                        try trades.append(.{
                            .entry_index = i,
                            .entry_price = price,
                            .side = .buy,
                        });
                    }
                },
                .short => {
                    if (position > 0) {
                        const price = candle.close * (1 - config.slippage);
                        capital = position * price * (1 - config.commission_rate);
                        position = 0;

                        trades.items[trades.items.len - 1].exit_index = i;
                        trades.items[trades.items.len - 1].exit_price = price;
                    }
                },
                .neutral => {},
            }
        }

        return .{
            .trades = trades.toOwnedSlice(),
            .final_capital = capital + position * candles[candles.len - 1].close,
        };
    }
};
```

---

## 性能优化策略

### 1. 内存对齐

```zig
// 确保数据对齐到 32 字节边界 (AVX2)
const aligned_data = std.mem.alignForward(usize, @intFromPtr(data.ptr), 32);
```

### 2. 预取

```zig
// 预取下一批数据到 L1 缓存
@prefetch(prices[i + 64 ..].ptr, .{ .locality = 3, .cache = .data });
```

### 3. 循环展开

```zig
// 手动展开循环减少分支
inline for (0..4) |j| {
    result[i + j] = process(prices[i + j]);
}
```

---

## 文件结构

```
src/backtest/vectorized/
├── mod.zig                 # 模块入口
├── backtester.zig          # VectorizedBacktester
├── data_loader.zig         # MmapDataLoader
├── simd_indicators.zig     # SIMD 指标计算
├── signal_generator.zig    # 批量信号生成
├── order_simulator.zig     # 批量订单模拟
└── tests/
    └── vectorized_test.zig # 测试
```

---

*Last updated: 2025-12-27*
