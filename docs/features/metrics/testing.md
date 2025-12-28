# Prometheus Metrics - 测试文档

> 测试覆盖和基准测试

**最后更新**: 2025-12-28

---

## 测试概览

| 类别 | 测试数 | 覆盖率 |
|------|--------|--------|
| 单元测试 | TBD | TBD |
| 集成测试 | TBD | TBD |
| 性能测试 | TBD | TBD |

---

## 单元测试

### Counter 测试

```zig
const std = @import("std");
const testing = std.testing;
const MetricsCollector = @import("metrics").MetricsCollector;

test "incTrade increments counter" {
    const allocator = testing.allocator;
    var collector = MetricsCollector.init(allocator);
    defer collector.deinit();

    collector.incTrade("sma_cross", "BTC-USDT", "buy");
    collector.incTrade("sma_cross", "BTC-USDT", "buy");

    const output = try collector.export(allocator);
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "zigquant_trades_total{strategy=\"sma_cross\",pair=\"BTC-USDT\",side=\"buy\"} 2") != null);
}

test "incApiRequest tracks different endpoints" {
    const allocator = testing.allocator;
    var collector = MetricsCollector.init(allocator);
    defer collector.deinit();

    collector.incApiRequest("GET", "/api/v1/strategies", 200);
    collector.incApiRequest("GET", "/api/v1/strategies", 200);
    collector.incApiRequest("POST", "/api/v1/orders", 201);
    collector.incApiRequest("GET", "/api/v1/strategies", 404);

    const output = try collector.export(allocator);
    defer allocator.free(output);

    // 验证不同标签组合
    try testing.expect(std.mem.indexOf(u8, output, "status=\"200\"} 2") != null);
    try testing.expect(std.mem.indexOf(u8, output, "status=\"201\"} 1") != null);
    try testing.expect(std.mem.indexOf(u8, output, "status=\"404\"} 1") != null);
}
```

### Gauge 测试

```zig
test "setWinRate updates value" {
    const allocator = testing.allocator;
    var collector = MetricsCollector.init(allocator);
    defer collector.deinit();

    collector.setWinRate("momentum", 0.55);
    collector.setWinRate("momentum", 0.62);  // 覆盖

    const output = try collector.export(allocator);
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "zigquant_win_rate{strategy=\"momentum\"} 0.62") != null);
}

test "setMaxDrawdown tracks single value" {
    const allocator = testing.allocator;
    var collector = MetricsCollector.init(allocator);
    defer collector.deinit();

    collector.setMaxDrawdown(0.15);

    const output = try collector.export(allocator);
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "zigquant_max_drawdown 0.15") != null);
}

test "setPositionSize handles multiple pairs" {
    const allocator = testing.allocator;
    var collector = MetricsCollector.init(allocator);
    defer collector.deinit();

    collector.setPositionSize("BTC-USDT", 0.5);
    collector.setPositionSize("ETH-USDT", 2.0);

    const output = try collector.export(allocator);
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "pair=\"BTC-USDT\"} 0.5") != null);
    try testing.expect(std.mem.indexOf(u8, output, "pair=\"ETH-USDT\"} 2") != null);
}
```

### Histogram 测试

```zig
test "Histogram.observe updates buckets cumulatively" {
    const allocator = testing.allocator;
    const buckets = [_]f64{ 0.01, 0.05, 0.1, 0.5, 1.0 };
    var histogram = Histogram.init(allocator, &buckets);
    defer histogram.deinit();

    histogram.observe(0.025);  // <= 0.05, 0.1, 0.5, 1.0
    histogram.observe(0.075);  // <= 0.1, 0.5, 1.0
    histogram.observe(0.008);  // <= 0.01, 0.05, 0.1, 0.5, 1.0

    try testing.expectEqual(@as(u64, 1), histogram.counts[0]);   // le=0.01
    try testing.expectEqual(@as(u64, 2), histogram.counts[1]);   // le=0.05
    try testing.expectEqual(@as(u64, 3), histogram.counts[2]);   // le=0.1
    try testing.expectEqual(@as(u64, 3), histogram.counts[3]);   // le=0.5
    try testing.expectEqual(@as(u64, 3), histogram.counts[4]);   // le=1.0
    try testing.expectEqual(@as(u64, 3), histogram.counts[5]);   // le=+Inf

    try testing.expectApproxEqAbs(0.108, histogram.sum, 0.001);
    try testing.expectEqual(@as(u64, 3), histogram.count);
}

test "observeOrderLatency records latency distribution" {
    const allocator = testing.allocator;
    var collector = MetricsCollector.init(allocator);
    defer collector.deinit();

    // 模拟不同延迟
    collector.observeOrderLatency(0.005);   // 5ms
    collector.observeOrderLatency(0.015);   // 15ms
    collector.observeOrderLatency(0.050);   // 50ms
    collector.observeOrderLatency(0.200);   // 200ms

    const output = try collector.export(allocator);
    defer allocator.free(output);

    // 验证累积桶
    try testing.expect(std.mem.indexOf(u8, output, "_bucket{le=\"0.005\"} 1") != null);
    try testing.expect(std.mem.indexOf(u8, output, "_bucket{le=\"0.025\"} 2") != null);
    try testing.expect(std.mem.indexOf(u8, output, "_bucket{le=\"+Inf\"} 4") != null);
    try testing.expect(std.mem.indexOf(u8, output, "_sum 0.27") != null);
    try testing.expect(std.mem.indexOf(u8, output, "_count 4") != null);
}

test "Histogram.reset clears all data" {
    const allocator = testing.allocator;
    const buckets = [_]f64{ 0.1, 0.5, 1.0 };
    var histogram = Histogram.init(allocator, &buckets);
    defer histogram.deinit();

    histogram.observe(0.25);
    histogram.observe(0.75);
    histogram.reset();

    try testing.expectEqual(@as(u64, 0), histogram.count);
    try testing.expectEqual(@as(f64, 0), histogram.sum);
    for (histogram.counts) |c| {
        try testing.expectEqual(@as(u64, 0), c);
    }
}
```

### 导出格式测试

```zig
test "export produces valid Prometheus format" {
    const allocator = testing.allocator;
    var collector = MetricsCollector.init(allocator);
    defer collector.deinit();

    collector.incTrade("test", "BTC-USDT", "buy");
    collector.setWinRate("test", 0.5);

    const output = try collector.export(allocator);
    defer allocator.free(output);

    // 验证 HELP 和 TYPE 注释
    try testing.expect(std.mem.indexOf(u8, output, "# HELP zigquant_trades_total") != null);
    try testing.expect(std.mem.indexOf(u8, output, "# TYPE zigquant_trades_total counter") != null);
    try testing.expect(std.mem.indexOf(u8, output, "# TYPE zigquant_win_rate gauge") != null);
}

test "export handles special characters in labels" {
    const allocator = testing.allocator;
    var collector = MetricsCollector.init(allocator);
    defer collector.deinit();

    // 包含特殊字符的标签
    collector.incApiRequest("GET", "/api/v1/backtest?id=123", 200);

    const output = try collector.export(allocator);
    defer allocator.free(output);

    // 应该正确转义
    try testing.expect(output.len > 0);
}

test "export includes uptime metric" {
    const allocator = testing.allocator;
    var collector = MetricsCollector.init(allocator);
    defer collector.deinit();

    std.time.sleep(100 * std.time.ns_per_ms);

    const output = try collector.export(allocator);
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "zigquant_uptime_seconds") != null);
}
```

### 线程安全测试

```zig
test "concurrent access is safe" {
    const allocator = testing.allocator;
    var collector = MetricsCollector.init(allocator);
    defer collector.deinit();

    const num_threads = 4;
    const ops_per_thread = 1000;

    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = try std.Thread.spawn(.{}, struct {
            fn run(c: *MetricsCollector) void {
                for (0..ops_per_thread) |_| {
                    c.incTrade("concurrent_test", "BTC-USDT", "buy");
                    c.observeOrderLatency(0.01);
                }
            }
        }.run, .{&collector});
    }

    for (threads) |t| {
        t.join();
    }

    // 验证总计数正确
    const output = try collector.export(allocator);
    defer allocator.free(output);

    // 应该有 num_threads * ops_per_thread = 4000 个交易
    try testing.expect(std.mem.indexOf(u8, output, "} 4000") != null);
}
```

---

## 集成测试

### HTTP 端点测试

```bash
#!/bin/bash
# test_metrics_endpoint.sh

BASE_URL="http://localhost:8080"

echo "Testing /metrics endpoint..."

# 基本请求
response=$(curl -s -w "%{http_code}" "$BASE_URL/metrics")
status_code="${response: -3}"
body="${response::-3}"

if [ "$status_code" != "200" ]; then
    echo "FAIL: Expected 200, got $status_code"
    exit 1
fi

# 验证 Content-Type
content_type=$(curl -s -I "$BASE_URL/metrics" | grep -i "content-type" | tr -d '\r')
if [[ ! "$content_type" =~ "text/plain" ]]; then
    echo "FAIL: Wrong content type: $content_type"
    exit 1
fi

# 验证格式
if [[ ! "$body" =~ "# HELP" ]]; then
    echo "FAIL: Missing HELP comments"
    exit 1
fi

if [[ ! "$body" =~ "# TYPE" ]]; then
    echo "FAIL: Missing TYPE comments"
    exit 1
fi

echo "PASS: All metrics endpoint tests passed"
```

### Prometheus 抓取验证

```yaml
# prometheus_test.yml
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: 'zigquant-test'
    static_configs:
      - targets: ['localhost:8080']
    metrics_path: '/metrics'
```

```bash
# 启动 Prometheus 并验证
docker run -d --name prom-test \
  -p 9090:9090 \
  -v $(pwd)/prometheus_test.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus

# 等待抓取
sleep 10

# 验证目标状态
curl -s "http://localhost:9090/api/v1/targets" | jq '.data.activeTargets[0].health'
# 应该返回 "up"

# 查询指标
curl -s "http://localhost:9090/api/v1/query?query=zigquant_uptime_seconds" | jq '.data.result'

# 清理
docker stop prom-test && docker rm prom-test
```

---

## 性能测试

### 基准测试

```zig
const std = @import("std");
const MetricsCollector = @import("metrics").MetricsCollector;

pub fn benchmarkIncCounter() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var collector = MetricsCollector.init(allocator);
    defer collector.deinit();

    const iterations = 1_000_000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        collector.incTrade("bench", "BTC-USDT", "buy");
    }

    const elapsed = std.time.nanoTimestamp() - start;
    const ns_per_op = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(iterations));

    std.debug.print("incTrade: {d:.2} ns/op ({d:.0} ops/sec)\n", .{
        ns_per_op,
        1_000_000_000.0 / ns_per_op,
    });
}

pub fn benchmarkObserveHistogram() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var collector = MetricsCollector.init(allocator);
    defer collector.deinit();

    const iterations = 1_000_000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const value = @as(f64, @floatFromInt(i % 100)) / 1000.0;
        collector.observeOrderLatency(value);
    }

    const elapsed = std.time.nanoTimestamp() - start;
    const ns_per_op = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(iterations));

    std.debug.print("observeOrderLatency: {d:.2} ns/op ({d:.0} ops/sec)\n", .{
        ns_per_op,
        1_000_000_000.0 / ns_per_op,
    });
}

pub fn benchmarkExport() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var collector = MetricsCollector.init(allocator);
    defer collector.deinit();

    // 预填充数据
    for (0..100) |_| {
        collector.incTrade("bench", "BTC-USDT", "buy");
        collector.observeOrderLatency(0.05);
    }

    const iterations = 10_000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        const output = collector.export(allocator) catch unreachable;
        allocator.free(output);
    }

    const elapsed = std.time.nanoTimestamp() - start;
    const ms_per_op = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(iterations)) / 1_000_000.0;

    std.debug.print("export: {d:.3} ms/op\n", .{ms_per_op});
}

pub fn main() void {
    std.debug.print("=== Metrics Benchmarks ===\n", .{});
    benchmarkIncCounter();
    benchmarkObserveHistogram();
    benchmarkExport();
}
```

### 预期性能

| 操作 | 目标 | 实测 |
|------|------|------|
| incCounter | < 100 ns | TBD |
| observeHistogram | < 200 ns | TBD |
| export (100 指标) | < 10 ms | TBD |
| export (1000 指标) | < 100 ms | TBD |

### 内存使用测试

```bash
# 监控内存使用
valgrind --tool=massif ./zigquant-metrics-bench

# 分析结果
ms_print massif.out.*
```

---

## 测试用例

### 正常情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| Counter 递增 | 正确递增计数 | 📋 待实现 |
| Gauge 设置 | 正确设置/更新值 | 📋 待实现 |
| Histogram 观测 | 正确更新桶和统计 | 📋 待实现 |
| Prometheus 导出 | 输出格式正确 | 📋 待实现 |
| 多标签组合 | 正确处理不同标签 | 📋 待实现 |

### 边界情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| 空收集器导出 | 返回有效空输出 | 📋 待实现 |
| 极大值 | 处理 f64 边界值 | 📋 待实现 |
| 高基数标签 | 限制标签组合数 | 📋 待实现 |
| 长标签值 | 正确截断或处理 | 📋 待实现 |

### 错误情况

| 测试用例 | 描述 | 状态 |
|----------|------|------|
| 内存不足 | 优雅处理 OOM | 📋 待实现 |
| 缓冲区溢出 | exportToBuffer 返回错误 | 📋 待实现 |

---

## 运行测试

```bash
# 运行所有测试
zig build test

# 运行特定模块测试
zig build test -- --filter "metrics"

# 运行基准测试
zig build bench

# 运行集成测试
./scripts/test_metrics.sh
```

---

*Last updated: 2025-12-28*
