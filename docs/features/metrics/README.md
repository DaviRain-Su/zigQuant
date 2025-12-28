# Prometheus Metrics - 监控指标

> 交易系统监控指标导出

**状态**: 📋 待开始
**版本**: v1.0.0
**Story**: [Story 049: Prometheus](../../stories/v1.0.0/STORY_049_PROMETHEUS.md)
**最后更新**: 2025-12-28

---

## 概述

zigQuant Metrics 模块提供 Prometheus 格式的监控指标导出，支持交易指标、系统指标和风控指标的实时监控。

### 为什么需要 Metrics？

- **实时监控**: 实时追踪交易系统状态
- **告警集成**: 与 Prometheus Alertmanager 集成
- **可视化**: 与 Grafana 无缝对接
- **性能分析**: 识别性能瓶颈

### 核心特性

- **交易指标**: 交易数、胜率、盈亏、夏普比率
- **系统指标**: 内存、运行时间、API 延迟
- **风控指标**: 回撤、VaR、仓位
- **Prometheus 格式**: 标准 OpenMetrics 格式
- **低开销**: < 1% CPU 开销

---

## 快速开始

### 基本使用

```zig
const std = @import("std");
const zigQuant = @import("zigQuant");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 创建指标收集器
    var collector = zigQuant.MetricsCollector.init(allocator);
    defer collector.deinit();

    // 2. 记录交易
    collector.incTrade("sma_cross", "BTC-USDT", "buy");
    collector.setTradePnL("sma_cross", "BTC-USDT", 150.50);
    collector.setWinRate("sma_cross", 0.65);

    // 3. 记录 API 指标
    collector.observeApiLatency("GET", "/api/v1/strategies", 0.025);
    collector.incApiRequest("GET", "/api/v1/strategies", 200);

    // 4. 导出 Prometheus 格式
    const output = try collector.export(allocator);
    defer allocator.free(output);

    std.debug.print("{s}\n", .{output});
}
```

### Prometheus 抓取配置

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'zigquant'
    static_configs:
      - targets: ['localhost:8080']
    metrics_path: '/metrics'
    scrape_interval: 15s
```

---

## 相关文档

- [API 参考](./api.md) - 完整的 API 文档
- [实现细节](./implementation.md) - 内部实现说明
- [测试文档](./testing.md) - 测试覆盖和基准
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 指标列表

### 交易指标

| 指标名 | 类型 | 标签 | 描述 |
|--------|------|------|------|
| `zigquant_trades_total` | Counter | strategy, pair, side | 交易总数 |
| `zigquant_trade_pnl` | Gauge | strategy, pair | 累计盈亏 |
| `zigquant_win_rate` | Gauge | strategy | 胜率 |
| `zigquant_sharpe_ratio` | Gauge | strategy | 夏普比率 |
| `zigquant_calmar_ratio` | Gauge | strategy | 卡尔马比率 |

### 订单指标

| 指标名 | 类型 | 标签 | 描述 |
|--------|------|------|------|
| `zigquant_orders_total` | Counter | status | 订单总数 |
| `zigquant_orders_active` | Gauge | - | 活跃订单数 |
| `zigquant_order_latency_seconds` | Histogram | - | 订单延迟 |

### 仓位指标

| 指标名 | 类型 | 标签 | 描述 |
|--------|------|------|------|
| `zigquant_position_size` | Gauge | pair | 仓位大小 |
| `zigquant_position_pnl` | Gauge | pair | 仓位盈亏 |
| `zigquant_position_count` | Gauge | - | 仓位数量 |
| `zigquant_max_drawdown` | Gauge | - | 最大回撤 |

### API 指标

| 指标名 | 类型 | 标签 | 描述 |
|--------|------|------|------|
| `zigquant_api_requests_total` | Counter | method, path, status | API 请求数 |
| `zigquant_api_latency_seconds` | Histogram | method, path | API 延迟 |
| `zigquant_api_connections_active` | Gauge | - | 活跃连接数 |

### 系统指标

| 指标名 | 类型 | 标签 | 描述 |
|--------|------|------|------|
| `zigquant_uptime_seconds` | Counter | - | 运行时间 |
| `zigquant_memory_bytes` | Gauge | type | 内存使用 |
| `zigquant_threads` | Gauge | - | 线程数 |
| `zigquant_exchange_connected` | Gauge | exchange | 交易所连接状态 |

### 风控指标

| 指标名 | 类型 | 标签 | 描述 |
|--------|------|------|------|
| `zigquant_var_95` | Gauge | - | 95% VaR |
| `zigquant_cvar_95` | Gauge | - | 95% CVaR |
| `zigquant_alerts_total` | Counter | level | 告警数 |

---

## 核心 API

### MetricsCollector

```zig
pub const MetricsCollector = struct {
    allocator: Allocator,

    // Counters
    trades_total: CounterMap,
    orders_total: CounterMap,
    api_requests_total: CounterMap,
    alerts_total: CounterMap,

    // Gauges
    trade_pnl: GaugeMap,
    win_rate: GaugeMap,
    sharpe_ratio: GaugeMap,
    position_size: GaugeMap,
    position_pnl: GaugeMap,
    max_drawdown: f64,
    memory_bytes: GaugeMap,
    uptime_start: i64,

    // Histograms
    order_latency: Histogram,
    api_latency: HistogramMap,

    pub fn init(allocator: Allocator) MetricsCollector;
    pub fn deinit(self: *MetricsCollector) void;

    // Counter methods
    pub fn incTrade(self: *MetricsCollector, strategy: []const u8, pair: []const u8, side: []const u8) void;
    pub fn incApiRequest(self: *MetricsCollector, method: []const u8, path: []const u8, status: u16) void;

    // Gauge methods
    pub fn setTradePnL(self: *MetricsCollector, strategy: []const u8, pair: []const u8, pnl: f64) void;
    pub fn setWinRate(self: *MetricsCollector, strategy: []const u8, rate: f64) void;

    // Histogram methods
    pub fn observeOrderLatency(self: *MetricsCollector, latency_seconds: f64) void;
    pub fn observeApiLatency(self: *MetricsCollector, method: []const u8, path: []const u8, latency: f64) void;

    // Export
    pub fn export(self: *MetricsCollector, allocator: Allocator) ![]const u8;
};
```

---

## Prometheus 输出示例

```prometheus
# HELP zigquant_trades_total Total number of trades
# TYPE zigquant_trades_total counter
zigquant_trades_total{strategy="sma_cross",pair="BTC-USDT",side="buy"} 150
zigquant_trades_total{strategy="sma_cross",pair="BTC-USDT",side="sell"} 148

# HELP zigquant_win_rate Strategy win rate
# TYPE zigquant_win_rate gauge
zigquant_win_rate{strategy="sma_cross"} 0.65

# HELP zigquant_order_latency_seconds Order execution latency
# TYPE zigquant_order_latency_seconds histogram
zigquant_order_latency_seconds_bucket{le="0.01"} 250
zigquant_order_latency_seconds_bucket{le="0.05"} 290
zigquant_order_latency_seconds_bucket{le="0.1"} 298
zigquant_order_latency_seconds_bucket{le="+Inf"} 298
zigquant_order_latency_seconds_sum 8.5
zigquant_order_latency_seconds_count 298

# HELP zigquant_uptime_seconds Time since start
# TYPE zigquant_uptime_seconds counter
zigquant_uptime_seconds 86400
```

---

## Grafana 仪表板

### 导入仪表板

1. 打开 Grafana: `http://localhost:3000`
2. 导入 → 上传 JSON
3. 选择 `deploy/grafana/dashboards/zigquant.json`

### 关键面板

- **总盈亏**: `sum(zigquant_trade_pnl)`
- **胜率仪表盘**: `avg(zigquant_win_rate)`
- **API P99 延迟**: `histogram_quantile(0.99, rate(zigquant_api_latency_seconds_bucket[5m]))`
- **每小时交易数**: `rate(zigquant_trades_total[1h]) * 3600`

---

## 性能指标

| 指标 | 目标值 |
|------|--------|
| 导出延迟 | < 100ms |
| CPU 开销 | < 1% |
| 内存占用 | < 10MB |
| 指标数量 | 支持 10,000+ |

---

## 未来改进

- [ ] OpenTelemetry 支持
- [ ] 自定义指标注册
- [ ] 指标聚合
- [ ] 远程写入 (Prometheus Remote Write)

---

*Last updated: 2025-12-28*
