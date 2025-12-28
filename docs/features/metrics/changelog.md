# Prometheus Metrics - 变更日志

> 版本历史记录

**最后更新**: 2025-12-28

---

## [未发布]

### 计划中 (v1.0.0)

#### 新增
- MetricsCollector 核心实现
- Counter 类型指标
  - `zigquant_trades_total` - 交易计数
  - `zigquant_orders_total` - 订单计数
  - `zigquant_api_requests_total` - API 请求计数
  - `zigquant_alerts_total` - 告警计数
- Gauge 类型指标
  - `zigquant_trade_pnl` - 交易盈亏
  - `zigquant_win_rate` - 策略胜率
  - `zigquant_sharpe_ratio` - 夏普比率
  - `zigquant_position_size` - 仓位大小
  - `zigquant_position_pnl` - 仓位盈亏
  - `zigquant_max_drawdown` - 最大回撤
  - `zigquant_memory_bytes` - 内存使用
- Histogram 类型指标
  - `zigquant_order_latency_seconds` - 订单延迟分布
  - `zigquant_api_latency_seconds` - API 延迟分布
- Prometheus text format 导出
- 线程安全 (互斥锁)
- `/metrics` HTTP 端点

---

## 计划版本

### v1.1.0 (规划中)

#### 新增
- 读写锁优化
- 高基数标签限制
- 指标缓存
- 增量导出

#### 变更
- 优化内存分配

### v1.2.0 (规划中)

#### 新增
- OpenMetrics 格式支持
- 自定义指标注册
- 远程写入 (Prometheus Remote Write)

---

## 版本规范

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/) 规范。

### 版本格式

```
MAJOR.MINOR.PATCH

- MAJOR: 不兼容的 API 变更
- MINOR: 向后兼容的新功能
- PATCH: 向后兼容的 bug 修复
```

### 变更类型

- **新增**: 新功能
- **变更**: 现有功能的变更
- **弃用**: 即将移除的功能
- **移除**: 已移除的功能
- **修复**: bug 修复
- **安全**: 安全相关修复

---

*Last updated: 2025-12-28*
