# Story 049: Prometheus Metrics

**Story ID**: STORY-049
**版本**: v1.0.0
**优先级**: P1
**状态**: 📋 待开始
**依赖**: Story 047 (REST API)

---

## 概述

实现 Prometheus 格式的监控指标导出，提供交易系统核心指标、API 性能指标和系统健康指标。支持与 Prometheus + Grafana 监控体系集成。

### 目标

1. 导出交易核心指标 (PnL, 胜率, 夏普比率等)
2. 导出 API 性能指标 (请求数, 延迟)
3. 导出系统健康指标 (内存, 连接数)
4. 提供 Grafana 仪表板模板
5. 指标更新延迟 < 1s

---

## 指标设计

### 交易指标

```prometheus
# 交易总数 (Counter)
zigquant_trades_total{strategy="sma_cross",pair="BTC-USDT",side="buy"} 150
zigquant_trades_total{strategy="sma_cross",pair="BTC-USDT",side="sell"} 148

# 交易盈亏 (Gauge)
zigquant_trade_pnl{strategy="sma_cross",pair="BTC-USDT"} 2500.50

# 胜率 (Gauge)
zigquant_win_rate{strategy="sma_cross"} 0.65

# 夏普比率 (Gauge)
zigquant_sharpe_ratio{strategy="sma_cross"} 1.85

# 卡尔马比率 (Gauge)
zigquant_calmar_ratio{strategy="sma_cross"} 2.10
```

### 订单指标

```prometheus
# 订单总数 (Counter)
zigquant_orders_total{status="filled"} 298
zigquant_orders_total{status="cancelled"} 12
zigquant_orders_total{status="rejected"} 3

# 订单延迟 (Histogram)
zigquant_order_latency_seconds_bucket{le="0.01"} 250
zigquant_order_latency_seconds_bucket{le="0.05"} 290
zigquant_order_latency_seconds_bucket{le="0.1"} 298
zigquant_order_latency_seconds_bucket{le="+Inf"} 298
zigquant_order_latency_seconds_sum 8.5
zigquant_order_latency_seconds_count 298

# 活跃订单数 (Gauge)
zigquant_orders_active 5
```

### 仓位指标

```prometheus
# 仓位大小 (Gauge)
zigquant_position_size{pair="BTC-USDT"} 0.5
zigquant_position_size{pair="ETH-USDT"} 2.0

# 仓位盈亏 (Gauge)
zigquant_position_pnl{pair="BTC-USDT"} 350.25
zigquant_position_pnl{pair="ETH-USDT"} -50.10

# 最大回撤 (Gauge)
zigquant_max_drawdown 0.082

# 仓位数量 (Gauge)
zigquant_position_count 2
```

### API 指标

```prometheus
# API 请求总数 (Counter)
zigquant_api_requests_total{method="GET",path="/api/v1/strategies",status="200"} 1500
zigquant_api_requests_total{method="POST",path="/api/v1/orders",status="201"} 298
zigquant_api_requests_total{method="GET",path="/api/v1/strategies",status="401"} 15

# API 延迟 (Histogram)
zigquant_api_latency_seconds_bucket{method="GET",path="/api/v1/strategies",le="0.01"} 1400
zigquant_api_latency_seconds_bucket{method="GET",path="/api/v1/strategies",le="0.05"} 1490
zigquant_api_latency_seconds_bucket{method="GET",path="/api/v1/strategies",le="0.1"} 1500
zigquant_api_latency_seconds_bucket{method="GET",path="/api/v1/strategies",le="+Inf"} 1500
zigquant_api_latency_seconds_sum{method="GET",path="/api/v1/strategies"} 12.5
zigquant_api_latency_seconds_count{method="GET",path="/api/v1/strategies"} 1500

# 活跃连接数 (Gauge)
zigquant_api_connections_active 25
```

### 系统指标

```prometheus
# 内存使用 (Gauge)
zigquant_memory_bytes{type="heap"} 52428800
zigquant_memory_bytes{type="rss"} 67108864

# 运行时间 (Counter)
zigquant_uptime_seconds 86400

# Goroutine/线程数 (Gauge)
zigquant_threads 8

# 交易所连接状态 (Gauge)
zigquant_exchange_connected{exchange="hyperliquid"} 1
zigquant_exchange_connected{exchange="binance"} 0
```

### 风控指标

```prometheus
# VaR 95% (Gauge)
zigquant_var_95 0.025

# CVaR/ES (Gauge)
zigquant_cvar_95 0.035

# 告警总数 (Counter)
zigquant_alerts_total{level="critical"} 2
zigquant_alerts_total{level="warning"} 15
zigquant_alerts_total{level="info"} 150
```

---

## 实现

### 指标收集器

```zig
// src/api/metrics/collector.zig
const std = @import("std");

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
            .order_latency = Histogram.init(allocator, &.{0.01, 0.05, 0.1, 0.5, 1.0}),
            .api_latency = std.StringHashMap(Histogram).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.trades_total.deinit();
        self.orders_total.deinit();
        self.api_requests_total.deinit();
        self.alerts_total.deinit();
        self.trade_pnl.deinit();
        self.win_rate.deinit();
        self.sharpe_ratio.deinit();
        self.position_size.deinit();
        self.position_pnl.deinit();
        self.memory_bytes.deinit();
        self.order_latency.deinit();
        var it = self.api_latency.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.api_latency.deinit();
    }

    // Counter 方法
    pub fn incTrade(self: *Self, strategy: []const u8, pair: []const u8, side: []const u8) void {
        const key = std.fmt.allocPrint(self.allocator, "{s},{s},{s}", .{strategy, pair, side}) catch return;
        defer self.allocator.free(key);
        const entry = self.trades_total.getOrPut(key) catch return;
        entry.value_ptr.* = if (entry.found_existing) entry.value_ptr.* + 1 else 1;
    }

    pub fn incApiRequest(self: *Self, method: []const u8, path: []const u8, status: u16) void {
        const key = std.fmt.allocPrint(self.allocator, "{s},{s},{d}", .{method, path, status}) catch return;
        defer self.allocator.free(key);
        const entry = self.api_requests_total.getOrPut(key) catch return;
        entry.value_ptr.* = if (entry.found_existing) entry.value_ptr.* + 1 else 1;
    }

    // Gauge 方法
    pub fn setTradePnL(self: *Self, strategy: []const u8, pair: []const u8, pnl: f64) void {
        const key = std.fmt.allocPrint(self.allocator, "{s},{s}", .{strategy, pair}) catch return;
        self.trade_pnl.put(key, pnl) catch {};
    }

    pub fn setWinRate(self: *Self, strategy: []const u8, rate: f64) void {
        self.win_rate.put(strategy, rate) catch {};
    }

    // Histogram 方法
    pub fn observeOrderLatency(self: *Self, latency_seconds: f64) void {
        self.order_latency.observe(latency_seconds);
    }

    pub fn observeApiLatency(self: *Self, method: []const u8, path: []const u8, latency_seconds: f64) void {
        const key = std.fmt.allocPrint(self.allocator, "{s},{s}", .{method, path}) catch return;
        const entry = self.api_latency.getOrPut(key) catch return;
        if (!entry.found_existing) {
            entry.value_ptr.* = Histogram.init(self.allocator, &.{0.01, 0.05, 0.1, 0.5, 1.0});
        }
        entry.value_ptr.observe(latency_seconds);
    }

    // 导出 Prometheus 格式
    pub fn export(self: *Self, allocator: Allocator) ![]const u8 {
        var output = std.ArrayList(u8).init(allocator);
        const writer = output.writer();

        // Trades
        try writer.writeAll("# HELP zigquant_trades_total Total number of trades\n");
        try writer.writeAll("# TYPE zigquant_trades_total counter\n");
        var it = self.trades_total.iterator();
        while (it.next()) |entry| {
            var parts = std.mem.splitScalar(u8, entry.key_ptr.*, ',');
            const strategy = parts.next() orelse "";
            const pair = parts.next() orelse "";
            const side = parts.next() orelse "";
            try writer.print("zigquant_trades_total{{strategy=\"{s}\",pair=\"{s}\",side=\"{s}\"}} {d}\n",
                .{strategy, pair, side, entry.value_ptr.*});
        }

        // Win Rate
        try writer.writeAll("\n# HELP zigquant_win_rate Strategy win rate\n");
        try writer.writeAll("# TYPE zigquant_win_rate gauge\n");
        var it2 = self.win_rate.iterator();
        while (it2.next()) |entry| {
            try writer.print("zigquant_win_rate{{strategy=\"{s}\"}} {d:.4}\n",
                .{entry.key_ptr.*, entry.value_ptr.*});
        }

        // Order Latency Histogram
        try writer.writeAll("\n# HELP zigquant_order_latency_seconds Order execution latency\n");
        try writer.writeAll("# TYPE zigquant_order_latency_seconds histogram\n");
        try self.order_latency.export(writer, "zigquant_order_latency_seconds");

        // Uptime
        try writer.writeAll("\n# HELP zigquant_uptime_seconds Time since start\n");
        try writer.writeAll("# TYPE zigquant_uptime_seconds counter\n");
        const uptime = std.time.timestamp() - self.uptime_start;
        try writer.print("zigquant_uptime_seconds {d}\n", .{uptime});

        // Memory
        try writer.writeAll("\n# HELP zigquant_memory_bytes Memory usage in bytes\n");
        try writer.writeAll("# TYPE zigquant_memory_bytes gauge\n");
        // 获取实际内存使用
        try writer.print("zigquant_memory_bytes{{type=\"heap\"}} {d}\n", .{getHeapUsage()});

        return output.toOwnedSlice();
    }
};
```

### Histogram 实现

```zig
// src/api/metrics/histogram.zig
pub const Histogram = struct {
    allocator: Allocator,
    buckets: []const f64,
    counts: []u64,
    sum: f64,
    count: u64,

    const Self = @This();

    pub fn init(allocator: Allocator, buckets: []const f64) Self {
        const counts = allocator.alloc(u64, buckets.len + 1) catch &.{};
        @memset(counts, 0);

        return .{
            .allocator = allocator,
            .buckets = buckets,
            .counts = counts,
            .sum = 0,
            .count = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.counts);
    }

    pub fn observe(self: *Self, value: f64) void {
        self.sum += value;
        self.count += 1;

        for (self.buckets, 0..) |bucket, i| {
            if (value <= bucket) {
                self.counts[i] += 1;
            }
        }
        self.counts[self.buckets.len] += 1; // +Inf bucket
    }

    pub fn export(self: *Self, writer: anytype, name: []const u8) !void {
        var cumulative: u64 = 0;
        for (self.buckets, 0..) |bucket, i| {
            cumulative += self.counts[i];
            try writer.print("{s}_bucket{{le=\"{d}\"}} {d}\n", .{name, bucket, cumulative});
        }
        try writer.print("{s}_bucket{{le=\"+Inf\"}} {d}\n", .{name, self.count});
        try writer.print("{s}_sum {d}\n", .{name, self.sum});
        try writer.print("{s}_count {d}\n", .{name, self.count});
    }
};
```

### Handler

```zig
// src/api/handlers/metrics.zig
const httpz = @import("httpz");
const MetricsCollector = @import("../metrics/collector.zig").MetricsCollector;

pub fn prometheus(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    const metrics = try ctx.server.metrics_collector.export(ctx.allocator);
    defer ctx.allocator.free(metrics);

    res.headers.put("Content-Type", "text/plain; version=0.0.4; charset=utf-8");
    try res.write(metrics);
}

pub fn get(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    // JSON 格式指标
    try res.json(.{
        .trades_total = ctx.server.metrics_collector.trades_total.count(),
        .orders_total = ctx.server.metrics_collector.orders_total.count(),
        .uptime_seconds = std.time.timestamp() - ctx.server.metrics_collector.uptime_start,
        .max_drawdown = ctx.server.metrics_collector.max_drawdown,
    });
}
```

---

## Prometheus 配置

### prometheus.yml

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'zigquant'
    static_configs:
      - targets: ['zigquant:8080']
    metrics_path: '/metrics'

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - 'alerts/*.yml'
```

### 告警规则 (alerts/zigquant.yml)

```yaml
groups:
  - name: zigquant
    rules:
      # 高回撤告警
      - alert: HighDrawdown
        expr: zigquant_max_drawdown > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High drawdown detected"
          description: "Drawdown is {{ $value | humanizePercentage }}"

      # 低胜率告警
      - alert: LowWinRate
        expr: zigquant_win_rate < 0.4
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Low win rate for strategy {{ $labels.strategy }}"

      # API 高延迟告警
      - alert: HighApiLatency
        expr: histogram_quantile(0.99, rate(zigquant_api_latency_seconds_bucket[5m])) > 0.5
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "API latency is too high"

      # 交易所断连告警
      - alert: ExchangeDisconnected
        expr: zigquant_exchange_connected == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Exchange {{ $labels.exchange }} is disconnected"
```

---

## Grafana 仪表板

### 仪表板 JSON (deploy/grafana/dashboards/zigquant.json)

```json
{
  "dashboard": {
    "title": "zigQuant Trading Dashboard",
    "uid": "zigquant-main",
    "panels": [
      {
        "title": "Total PnL",
        "type": "stat",
        "gridPos": { "x": 0, "y": 0, "w": 6, "h": 4 },
        "targets": [{
          "expr": "sum(zigquant_trade_pnl)"
        }],
        "fieldConfig": {
          "defaults": {
            "unit": "currencyUSD",
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "value": null, "color": "red" },
                { "value": 0, "color": "green" }
              ]
            }
          }
        }
      },
      {
        "title": "Win Rate",
        "type": "gauge",
        "gridPos": { "x": 6, "y": 0, "w": 6, "h": 4 },
        "targets": [{
          "expr": "avg(zigquant_win_rate)"
        }],
        "fieldConfig": {
          "defaults": {
            "unit": "percentunit",
            "min": 0,
            "max": 1,
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "value": null, "color": "red" },
                { "value": 0.4, "color": "yellow" },
                { "value": 0.5, "color": "green" }
              ]
            }
          }
        }
      },
      {
        "title": "Max Drawdown",
        "type": "stat",
        "gridPos": { "x": 12, "y": 0, "w": 6, "h": 4 },
        "targets": [{
          "expr": "zigquant_max_drawdown"
        }],
        "fieldConfig": {
          "defaults": {
            "unit": "percentunit",
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "value": null, "color": "green" },
                { "value": 0.05, "color": "yellow" },
                { "value": 0.1, "color": "red" }
              ]
            }
          }
        }
      },
      {
        "title": "Trades per Hour",
        "type": "timeseries",
        "gridPos": { "x": 0, "y": 4, "w": 12, "h": 8 },
        "targets": [{
          "expr": "rate(zigquant_trades_total[1h]) * 3600",
          "legendFormat": "{{ strategy }}"
        }]
      },
      {
        "title": "API Latency (p99)",
        "type": "timeseries",
        "gridPos": { "x": 12, "y": 4, "w": 12, "h": 8 },
        "targets": [{
          "expr": "histogram_quantile(0.99, rate(zigquant_api_latency_seconds_bucket[5m]))",
          "legendFormat": "{{ method }} {{ path }}"
        }],
        "fieldConfig": {
          "defaults": { "unit": "s" }
        }
      },
      {
        "title": "Order Latency Distribution",
        "type": "heatmap",
        "gridPos": { "x": 0, "y": 12, "w": 12, "h": 8 },
        "targets": [{
          "expr": "rate(zigquant_order_latency_seconds_bucket[5m])"
        }]
      },
      {
        "title": "Memory Usage",
        "type": "timeseries",
        "gridPos": { "x": 12, "y": 12, "w": 12, "h": 8 },
        "targets": [{
          "expr": "zigquant_memory_bytes",
          "legendFormat": "{{ type }}"
        }],
        "fieldConfig": {
          "defaults": { "unit": "bytes" }
        }
      }
    ]
  }
}
```

---

## 集成到 ApiServer

```zig
// src/api/server.zig
const MetricsCollector = @import("metrics/collector.zig").MetricsCollector;

pub const ApiServer = struct {
    // ... 其他字段
    metrics_collector: MetricsCollector,

    pub fn init(allocator: Allocator, config: ApiConfig, deps: Dependencies) !*Self {
        const self = try allocator.create(Self);

        self.* = .{
            // ...
            .metrics_collector = MetricsCollector.init(allocator),
        };

        // 中间件注入指标收集
        self.server.middleware(metricsMiddleware(&self.metrics_collector));

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.metrics_collector.deinit();
        // ...
    }
};

// 指标收集中间件
fn metricsMiddleware(collector: *MetricsCollector) httpz.Middleware {
    return struct {
        fn handle(ctx: *httpz.Request.Context, req: *httpz.Request, res: *httpz.Response) !void {
            const start = std.time.nanoTimestamp();

            defer {
                const end = std.time.nanoTimestamp();
                const latency = @as(f64, @floatFromInt(end - start)) / 1_000_000_000.0;

                collector.observeApiLatency(@tagName(req.method), req.path, latency);
                collector.incApiRequest(@tagName(req.method), req.path, @intFromEnum(res.status));
            }

            return ctx.next(req, res);
        }
    }.handle;
}
```

---

## 验收标准

### 功能要求

- [ ] `/metrics` 端点返回 Prometheus 格式
- [ ] 交易指标 (trades_total, trade_pnl, win_rate)
- [ ] 订单指标 (orders_total, order_latency)
- [ ] 仓位指标 (position_size, position_pnl)
- [ ] API 指标 (requests_total, latency)
- [ ] 系统指标 (memory, uptime)
- [ ] 风控指标 (max_drawdown, var_95)

### 性能要求

- [ ] 指标导出延迟 < 100ms
- [ ] 指标收集开销 < 1% CPU
- [ ] 内存占用 < 10MB

### 集成要求

- [ ] Prometheus 可成功抓取
- [ ] Grafana 仪表板可用
- [ ] 告警规则生效

---

## 相关文档

- [v1.0.0 Overview](./OVERVIEW.md)
- [Story 047: REST API](./STORY_047_REST_API.md)
- [Story 050: Docker](./STORY_050_DOCKER.md)

---

*最后更新: 2025-12-28*
