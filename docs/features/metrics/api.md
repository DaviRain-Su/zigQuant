# Prometheus Metrics - API 参考

> 完整的 API 文档

**最后更新**: 2025-12-28

---

## MetricsCollector

指标收集器，负责收集和导出 Prometheus 格式的监控指标。

### 结构体

```zig
pub const MetricsCollector = struct {
    allocator: Allocator,

    // Counters
    trades_total: std.StringHashMap(u64),
    orders_total: std.StringHashMap(u64),
    api_requests_total: std.StringHashMap(u64),
    alerts_total: std.StringHashMap(u64),

    // Gauges
    trade_pnl: std.StringHashMap(f64),
    win_rate: std.StringHashMap(f64),
    sharpe_ratio: std.StringHashMap(f64),
    position_size: std.StringHashMap(f64),
    position_pnl: std.StringHashMap(f64),
    max_drawdown: f64,
    memory_bytes: std.StringHashMap(u64),
    uptime_start: i64,

    // Histograms
    order_latency: Histogram,
    api_latency: std.StringHashMap(Histogram),

    // 线程安全
    mutex: std.Thread.Mutex,
};
```

### 初始化和清理

#### init

```zig
pub fn init(allocator: Allocator) MetricsCollector
```

创建新的指标收集器实例。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `allocator` | `Allocator` | 内存分配器 |

**返回**: `MetricsCollector` 实例

**示例**:
```zig
var collector = MetricsCollector.init(allocator);
defer collector.deinit();
```

#### deinit

```zig
pub fn deinit(self: *MetricsCollector) void
```

释放收集器占用的所有资源。

**示例**:
```zig
collector.deinit();
```

---

## Counter 方法

Counter 是只增不减的计数器，用于记录累计值。

### incTrade

```zig
pub fn incTrade(
    self: *MetricsCollector,
    strategy: []const u8,
    pair: []const u8,
    side: []const u8,
) void
```

增加交易计数。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `strategy` | `[]const u8` | 策略名称 |
| `pair` | `[]const u8` | 交易对 (如 "BTC-USDT") |
| `side` | `[]const u8` | 方向 ("buy" 或 "sell") |

**示例**:
```zig
collector.incTrade("sma_cross", "BTC-USDT", "buy");
```

**Prometheus 输出**:
```
zigquant_trades_total{strategy="sma_cross",pair="BTC-USDT",side="buy"} 1
```

### incOrder

```zig
pub fn incOrder(
    self: *MetricsCollector,
    status: []const u8,
) void
```

增加订单计数。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `status` | `[]const u8` | 订单状态 ("filled", "cancelled", "rejected") |

**示例**:
```zig
collector.incOrder("filled");
```

### incApiRequest

```zig
pub fn incApiRequest(
    self: *MetricsCollector,
    method: []const u8,
    path: []const u8,
    status: u16,
) void
```

增加 API 请求计数。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `method` | `[]const u8` | HTTP 方法 ("GET", "POST", etc.) |
| `path` | `[]const u8` | 请求路径 |
| `status` | `u16` | HTTP 状态码 |

**示例**:
```zig
collector.incApiRequest("GET", "/api/v1/strategies", 200);
```

**Prometheus 输出**:
```
zigquant_api_requests_total{method="GET",path="/api/v1/strategies",status="200"} 1
```

### incAlert

```zig
pub fn incAlert(
    self: *MetricsCollector,
    level: []const u8,
) void
```

增加告警计数。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `level` | `[]const u8` | 告警级别 ("info", "warning", "critical") |

**示例**:
```zig
collector.incAlert("warning");
```

---

## Gauge 方法

Gauge 是可增可减的数值，用于记录当前状态。

### setTradePnL

```zig
pub fn setTradePnL(
    self: *MetricsCollector,
    strategy: []const u8,
    pair: []const u8,
    pnl: f64,
) void
```

设置交易盈亏。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `strategy` | `[]const u8` | 策略名称 |
| `pair` | `[]const u8` | 交易对 |
| `pnl` | `f64` | 盈亏金额 |

**示例**:
```zig
collector.setTradePnL("sma_cross", "BTC-USDT", 1250.50);
```

### setWinRate

```zig
pub fn setWinRate(
    self: *MetricsCollector,
    strategy: []const u8,
    rate: f64,
) void
```

设置策略胜率。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `strategy` | `[]const u8` | 策略名称 |
| `rate` | `f64` | 胜率 (0.0 - 1.0) |

**示例**:
```zig
collector.setWinRate("sma_cross", 0.65);
```

### setSharpeRatio

```zig
pub fn setSharpeRatio(
    self: *MetricsCollector,
    strategy: []const u8,
    ratio: f64,
) void
```

设置夏普比率。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `strategy` | `[]const u8` | 策略名称 |
| `ratio` | `f64` | 夏普比率 |

**示例**:
```zig
collector.setSharpeRatio("sma_cross", 1.85);
```

### setPositionSize

```zig
pub fn setPositionSize(
    self: *MetricsCollector,
    pair: []const u8,
    size: f64,
) void
```

设置仓位大小。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `pair` | `[]const u8` | 交易对 |
| `size` | `f64` | 仓位数量 |

**示例**:
```zig
collector.setPositionSize("BTC-USDT", 0.5);
```

### setPositionPnL

```zig
pub fn setPositionPnL(
    self: *MetricsCollector,
    pair: []const u8,
    pnl: f64,
) void
```

设置仓位盈亏。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `pair` | `[]const u8` | 交易对 |
| `pnl` | `f64` | 未实现盈亏 |

**示例**:
```zig
collector.setPositionPnL("BTC-USDT", 320.00);
```

### setMaxDrawdown

```zig
pub fn setMaxDrawdown(
    self: *MetricsCollector,
    drawdown: f64,
) void
```

设置最大回撤。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `drawdown` | `f64` | 最大回撤比例 (0.0 - 1.0) |

**示例**:
```zig
collector.setMaxDrawdown(0.15);  // 15% 回撤
```

### setMemoryBytes

```zig
pub fn setMemoryBytes(
    self: *MetricsCollector,
    mem_type: []const u8,
    bytes: u64,
) void
```

设置内存使用量。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `mem_type` | `[]const u8` | 内存类型 ("heap", "stack", "total") |
| `bytes` | `u64` | 字节数 |

**示例**:
```zig
collector.setMemoryBytes("heap", 52_428_800);  // 50 MB
```

---

## Histogram 方法

Histogram 用于记录数值分布，如延迟统计。

### observeOrderLatency

```zig
pub fn observeOrderLatency(
    self: *MetricsCollector,
    latency_seconds: f64,
) void
```

记录订单延迟。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `latency_seconds` | `f64` | 延迟时间 (秒) |

**示例**:
```zig
collector.observeOrderLatency(0.025);  // 25ms
```

**Prometheus 输出**:
```
zigquant_order_latency_seconds_bucket{le="0.01"} 0
zigquant_order_latency_seconds_bucket{le="0.025"} 1
zigquant_order_latency_seconds_bucket{le="0.05"} 1
zigquant_order_latency_seconds_bucket{le="+Inf"} 1
zigquant_order_latency_seconds_sum 0.025
zigquant_order_latency_seconds_count 1
```

### observeApiLatency

```zig
pub fn observeApiLatency(
    self: *MetricsCollector,
    method: []const u8,
    path: []const u8,
    latency: f64,
) void
```

记录 API 延迟。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `method` | `[]const u8` | HTTP 方法 |
| `path` | `[]const u8` | 请求路径 |
| `latency` | `f64` | 延迟时间 (秒) |

**示例**:
```zig
collector.observeApiLatency("GET", "/api/v1/strategies", 0.015);
```

---

## 导出方法

### export

```zig
pub fn export(
    self: *MetricsCollector,
    allocator: Allocator,
) ![]const u8
```

导出 Prometheus 格式的指标文本。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `allocator` | `Allocator` | 用于分配输出缓冲区 |

**返回**: Prometheus 格式的文本，调用者负责释放

**错误**:
- `error.OutOfMemory` - 内存分配失败

**示例**:
```zig
const output = try collector.export(allocator);
defer allocator.free(output);

std.debug.print("{s}", .{output});
```

### exportToBuffer

```zig
pub fn exportToBuffer(
    self: *MetricsCollector,
    buffer: []u8,
) !usize
```

导出指标到预分配的缓冲区。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `buffer` | `[]u8` | 预分配的缓冲区 |

**返回**: 写入的字节数

**错误**:
- `error.NoSpaceLeft` - 缓冲区不足

**示例**:
```zig
var buffer: [65536]u8 = undefined;
const len = try collector.exportToBuffer(&buffer);
const output = buffer[0..len];
```

---

## Histogram

直方图结构，用于分布统计。

### 结构体

```zig
pub const Histogram = struct {
    allocator: Allocator,
    buckets: []const f64,
    counts: []u64,
    sum: f64,
    count: u64,
};
```

### init

```zig
pub fn init(allocator: Allocator, buckets: []const f64) Histogram
```

创建新的直方图。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `allocator` | `Allocator` | 内存分配器 |
| `buckets` | `[]const f64` | 桶边界值数组 |

**示例**:
```zig
const buckets = [_]f64{ 0.01, 0.05, 0.1, 0.5, 1.0 };
var histogram = Histogram.init(allocator, &buckets);
defer histogram.deinit();
```

### observe

```zig
pub fn observe(self: *Histogram, value: f64) void
```

记录一个观测值。

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `value` | `f64` | 观测值 |

**示例**:
```zig
histogram.observe(0.025);
histogram.observe(0.150);
```

### reset

```zig
pub fn reset(self: *Histogram) void
```

重置直方图的所有计数。

**示例**:
```zig
histogram.reset();
```

### deinit

```zig
pub fn deinit(self: *Histogram) void
```

释放直方图资源。

---

## 默认配置

### 默认桶边界

```zig
pub const default_latency_buckets = [_]f64{
    0.005,  // 5ms
    0.01,   // 10ms
    0.025,  // 25ms
    0.05,   // 50ms
    0.1,    // 100ms
    0.25,   // 250ms
    0.5,    // 500ms
    1.0,    // 1s
    2.5,    // 2.5s
    5.0,    // 5s
    10.0,   // 10s
};
```

---

## 线程安全

所有公开方法都是线程安全的，内部使用互斥锁保护共享状态。

```zig
pub fn incTrade(self: *Self, ...) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    // ... 安全操作
}
```

**注意**: `export()` 方法会持有锁直到导出完成，高频导出可能影响性能。

---

## 完整示例

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建收集器
    var collector = zigQuant.MetricsCollector.init(allocator);
    defer collector.deinit();

    // 模拟交易活动
    for (0..100) |_| {
        collector.incTrade("momentum", "ETH-USDT", "buy");
        collector.observeOrderLatency(0.015 + @as(f64, @floatFromInt(std.crypto.random.int(u8))) / 1000.0);
    }

    // 设置策略指标
    collector.setWinRate("momentum", 0.58);
    collector.setSharpeRatio("momentum", 1.42);
    collector.setMaxDrawdown(0.12);

    // 记录 API 指标
    collector.incApiRequest("GET", "/api/v1/positions", 200);
    collector.observeApiLatency("GET", "/api/v1/positions", 0.008);

    // 导出并打印
    const output = try collector.export(allocator);
    defer allocator.free(output);

    std.debug.print("{s}\n", .{output});
}
```

---

*Last updated: 2025-12-28*
