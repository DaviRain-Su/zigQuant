# Story 051: 运维文档

**Story ID**: STORY-051
**版本**: v1.0.0
**优先级**: P2
**状态**: 📋 待开始
**依赖**: Story 047-050

---

## 概述

编写完整的生产环境运维文档，包括部署指南、配置手册、监控告警设置、故障排查指南和性能调优建议。

### 目标

1. 部署指南 - 从零开始部署
2. 配置手册 - 所有配置项说明
3. 监控告警 - Prometheus + Grafana 配置
4. 故障排查 - 常见问题解决
5. 性能调优 - 优化建议

---

## 文档结构

```
docs/operations/
├── README.md                    # 运维文档索引
├── deployment/
│   ├── quick-start.md           # 快速开始
│   ├── docker-deployment.md     # Docker 部署
│   ├── bare-metal.md            # 裸机部署
│   ├── kubernetes.md            # K8s 部署 (规划)
│   └── upgrade.md               # 升级指南
├── configuration/
│   ├── config-reference.md      # 配置参考
│   ├── environment.md           # 环境变量
│   └── security.md              # 安全配置
├── monitoring/
│   ├── prometheus-setup.md      # Prometheus 配置
│   ├── grafana-dashboards.md    # Grafana 仪表板
│   ├── alerting.md              # 告警配置
│   └── logging.md               # 日志管理
├── troubleshooting/
│   ├── common-issues.md         # 常见问题
│   ├── debug-guide.md           # 调试指南
│   └── recovery.md              # 故障恢复
└── performance/
    ├── tuning.md                # 性能调优
    ├── benchmarks.md            # 基准测试
    └── capacity-planning.md     # 容量规划
```

---

## 文档内容

### 1. 快速开始 (quick-start.md)

```markdown
# 快速开始

## 系统要求

- Linux (Ubuntu 22.04+, CentOS 8+) 或 macOS 12+
- Docker 24+ 和 Docker Compose 2.20+
- 2 CPU cores, 4GB RAM (最低)
- 10GB 磁盘空间

## 5 分钟部署

### 1. 获取代码

git clone https://github.com/DaviRain-Su/zigQuant.git
cd zigQuant

### 2. 配置环境

cp .env.example .env
# 编辑 .env 设置必要的配置

### 3. 启动服务

docker-compose up -d

### 4. 验证部署

# 检查服务状态
docker-compose ps

# 检查健康状态
curl http://localhost:8080/health

# 查看日志
docker-compose logs -f zigquant

### 5. 访问服务

- API: http://localhost:8080
- Dashboard: http://localhost:8080
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000 (admin/admin)

## 下一步

- [配置交易所 API](./configuration/config-reference.md#exchange)
- [设置通知渠道](./configuration/config-reference.md#notifications)
- [配置监控告警](./monitoring/alerting.md)
```

### 2. 配置参考 (config-reference.md)

```markdown
# 配置参考

## 配置文件格式

zigQuant 使用 JSON 格式配置文件，默认位置: `/etc/zigquant/config.json`

## 完整配置示例

{
  "api": { ... },
  "exchange": { ... },
  "trading": { ... },
  "notifications": { ... },
  "logging": { ... }
}

## 配置项说明

### api

| 字段 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| host | string | "0.0.0.0" | 监听地址 |
| port | number | 8080 | 监听端口 |
| workers | number | 4 | 工作线程数 |
| jwt_secret | string | - | JWT 签名密钥 (必填) |
| jwt_expiry_hours | number | 24 | Token 过期时间 |
| cors_origins | string[] | ["*"] | CORS 允许的源 |

### exchange

| 字段 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| name | string | "hyperliquid" | 交易所名称 |
| api_key | string | - | API Key |
| api_secret | string | - | API Secret |
| testnet | boolean | true | 是否使用测试网 |

### trading

| 字段 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| max_position_size | number | 1.0 | 最大仓位比例 |
| max_daily_loss | number | 0.05 | 最大日亏损 (5%) |
| default_leverage | number | 1 | 默认杠杆 |

### notifications.telegram

| 字段 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| enabled | boolean | false | 是否启用 |
| bot_token | string | - | Bot Token |
| chat_id | string | - | Chat ID |

### notifications.email

| 字段 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| enabled | boolean | false | 是否启用 |
| provider | string | "sendgrid" | 邮件服务商 |
| api_key | string | - | API Key |
| from | string | - | 发件人地址 |
| to | string[] | - | 收件人列表 |

### logging

| 字段 | 类型 | 默认值 | 描述 |
|------|------|--------|------|
| level | string | "info" | 日志级别 (debug/info/warn/error) |
| format | string | "json" | 日志格式 (json/text) |

## 环境变量覆盖

配置项可通过环境变量覆盖，格式: `ZIGQUANT_<SECTION>_<KEY>`

# 示例
export ZIGQUANT_API_PORT=9000
export ZIGQUANT_LOGGING_LEVEL=debug
```

### 3. 告警配置 (alerting.md)

```markdown
# 告警配置

## Prometheus 告警规则

### 文件位置

deploy/prometheus/alerts/zigquant.yml

### 推荐告警规则

#### 交易告警

groups:
  - name: trading
    rules:
      # 高回撤
      - alert: HighDrawdown
        expr: zigquant_max_drawdown > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "回撤超过 10%"
          description: "当前回撤: {{ $value | humanizePercentage }}"

      # 低胜率
      - alert: LowWinRate
        expr: zigquant_win_rate{strategy!=""} < 0.4
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "策略 {{ $labels.strategy }} 胜率低于 40%"

      # 连续亏损
      - alert: ConsecutiveLosses
        expr: zigquant_consecutive_losses > 5
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "连续亏损超过 5 次"

#### 系统告警

  - name: system
    rules:
      # API 高延迟
      - alert: HighApiLatency
        expr: histogram_quantile(0.99, rate(zigquant_api_latency_seconds_bucket[5m])) > 0.5
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "API P99 延迟超过 500ms"

      # 服务不可用
      - alert: ServiceDown
        expr: up{job="zigquant"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "zigQuant 服务不可用"

      # 内存使用过高
      - alert: HighMemoryUsage
        expr: zigquant_memory_bytes{type="heap"} > 500000000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "内存使用超过 500MB"

#### 交易所告警

  - name: exchange
    rules:
      # 交易所断连
      - alert: ExchangeDisconnected
        expr: zigquant_exchange_connected == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "交易所 {{ $labels.exchange }} 断开连接"

## Alertmanager 配置

### 文件位置

deploy/alertmanager/alertmanager.yml

### 配置示例

global:
  resolve_timeout: 5m

route:
  receiver: 'default'
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - match:
        severity: critical
      receiver: 'critical'
      continue: true
    - match:
        severity: warning
      receiver: 'warning'

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://zigquant:8080/api/v1/webhooks/alertmanager'

  - name: 'critical'
    telegram_configs:
      - bot_token: '${TELEGRAM_BOT_TOKEN}'
        chat_id: ${TELEGRAM_CHAT_ID}
        message: |
          {{ range .Alerts }}
          *{{ .Labels.alertname }}*
          {{ .Annotations.summary }}
          {{ .Annotations.description }}
          {{ end }}

  - name: 'warning'
    email_configs:
      - to: 'admin@example.com'
        from: 'alerts@example.com'
        smarthost: 'smtp.example.com:587'
        auth_username: 'alerts@example.com'
        auth_password: '${SMTP_PASSWORD}'

## 告警级别定义

| 级别 | 描述 | 通知渠道 | 响应时间 |
|------|------|----------|----------|
| critical | 影响交易，需立即处理 | Telegram + Email | < 5 分钟 |
| warning | 可能影响性能，需关注 | Email | < 1 小时 |
| info | 信息通知 | Dashboard | 无 |
```

### 4. 故障排查 (common-issues.md)

```markdown
# 常见问题

## 启动问题

### 服务无法启动

**症状**: `docker-compose up` 后服务立即退出

**排查步骤**:

# 查看日志
docker-compose logs zigquant

# 检查配置文件
docker-compose exec zigquant cat /etc/zigquant/config.json

**常见原因**:
1. 配置文件格式错误 - 检查 JSON 语法
2. 端口被占用 - `lsof -i :8080`
3. 权限问题 - 检查文件权限

### 健康检查失败

**症状**: 容器状态显示 `unhealthy`

**排查步骤**:

# 手动执行健康检查
docker-compose exec zigquant wget -q --spider http://localhost:8080/health

# 检查端口监听
docker-compose exec zigquant netstat -tlnp

## 连接问题

### 交易所连接失败

**症状**: 日志显示 "Failed to connect to exchange"

**排查步骤**:

# 检查网络连通性
docker-compose exec zigquant wget -q --spider https://api.hyperliquid.xyz

# 检查 API 密钥
docker-compose exec zigquant env | grep API

**常见原因**:
1. API 密钥错误
2. IP 白名单未配置
3. 网络防火墙限制

### WebSocket 断开

**症状**: 日志显示 "WebSocket disconnected"

**解决方案**:
1. 检查网络稳定性
2. 增加重连间隔
3. 使用代理

## 性能问题

### API 响应慢

**症状**: API 响应时间 > 1s

**排查步骤**:

# 检查系统资源
docker stats zigquant

# 检查请求队列
curl http://localhost:8080/api/v1/metrics | grep queue

**解决方案**:
1. 增加工作线程数
2. 优化数据库查询
3. 添加缓存

### 内存泄漏

**症状**: 内存使用持续增长

**排查步骤**:

# 监控内存趋势
watch -n 5 'docker stats --no-stream zigquant'

# 检查指标
curl http://localhost:8080/metrics | grep memory

**解决方案**:
1. 检查是否有未释放的资源
2. 定期重启服务
3. 升级到最新版本

## 数据问题

### 回测结果异常

**症状**: 回测收益率不合理

**排查步骤**:
1. 检查数据源质量
2. 验证策略逻辑
3. 检查手续费设置

### 仓位不同步

**症状**: 显示仓位与实际不符

**解决方案**:

# 触发仓位同步
curl -X POST http://localhost:8080/api/v1/sync/positions

## 日志分析

### 日志位置

docker-compose logs zigquant > zigquant.log

### 常用日志过滤

# 错误日志
grep "error" zigquant.log

# 交易日志
grep "trade" zigquant.log

# 特定时间段
grep "2024-12-28T10:" zigquant.log
```

### 5. 性能调优 (tuning.md)

```markdown
# 性能调优

## 系统配置

### 文件描述符限制

# 临时设置
ulimit -n 65535

# 永久设置 (/etc/security/limits.conf)
zigquant soft nofile 65535
zigquant hard nofile 65535

### 网络优化

# /etc/sysctl.conf
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535

## API 服务调优

### 工作线程

根据 CPU 核心数设置:
- 推荐: CPU cores * 2
- 最大: CPU cores * 4

{
  "api": {
    "workers": 8
  }
}

### 连接池

# 配置交易所连接池
{
  "exchange": {
    "max_connections": 10,
    "connection_timeout_ms": 5000
  }
}

## 监控指标阈值

| 指标 | 正常范围 | 告警阈值 |
|------|----------|----------|
| API P99 延迟 | < 50ms | > 100ms |
| 内存使用 | < 100MB | > 200MB |
| CPU 使用 | < 50% | > 80% |
| 订单延迟 | < 100ms | > 500ms |

## 容量规划

### 策略数量

| 策略数 | 推荐配置 |
|--------|----------|
| 1-5 | 2 CPU, 4GB RAM |
| 5-20 | 4 CPU, 8GB RAM |
| 20+ | 8 CPU, 16GB RAM |

### 存储

| 数据类型 | 估算大小/天 |
|----------|-------------|
| 日志 | 100MB |
| 指标 | 50MB |
| 交易记录 | 10MB |

## 基准测试

### API 性能测试

# 使用 wrk 测试
wrk -t12 -c400 -d30s http://localhost:8080/health

### 预期结果

| 端点 | QPS | P99 延迟 |
|------|-----|----------|
| /health | 50,000+ | < 1ms |
| /api/v1/strategies | 10,000+ | < 10ms |
| /api/v1/backtest | 100+ | < 1s |
```

---

## 验收标准

### 文档完整性

- [ ] 快速开始指南
- [ ] 配置参考手册
- [ ] 部署指南 (Docker/裸机)
- [ ] 监控配置指南
- [ ] 告警配置指南
- [ ] 故障排查指南
- [ ] 性能调优指南

### 文档质量

- [ ] 步骤清晰可执行
- [ ] 命令可复制粘贴
- [ ] 配置示例完整
- [ ] 常见问题覆盖

---

## 相关文档

- [v1.0.0 Overview](./OVERVIEW.md)
- [Story 050: Docker](./STORY_050_DOCKER.md)

---

*最后更新: 2025-12-28*
