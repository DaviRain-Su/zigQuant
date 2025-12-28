# Docker 部署 - 实现细节

> 深入了解内部实现

**最后更新**: 2025-12-28

---

## 架构概述

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker Compose Stack                      │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  zigQuant   │  │ Prometheus  │  │      Grafana        │  │
│  │  (API)      │→ │ (Metrics)   │→ │   (Dashboard)       │  │
│  │  :8080      │  │  :9090      │  │      :3000          │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│         │                │                    │              │
│         ▼                ▼                    ▼              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ zigquant-   │  │ prometheus- │  │   grafana-data      │  │
│  │   data      │  │    data     │  │                     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 多阶段构建

### 构建阶段 (Builder)

```dockerfile
FROM alpine:3.19 AS builder

# 安装构建依赖
RUN apk add --no-cache \
    zig \
    git \
    ca-certificates

WORKDIR /app

# 复制依赖文件 (利用缓存)
COPY build.zig .
COPY build.zig.zon .

# 预取依赖
RUN zig build --fetch-only 2>/dev/null || true

# 复制源码
COPY src/ src/
COPY libs/ libs/

# 构建 Release 版本
RUN zig build -Doptimize=ReleaseSafe \
    && strip zig-out/bin/zigquant
```

**优化点**:
1. 分层复制利用缓存
2. 先复制 `build.zig.zon` 预取依赖
3. 使用 `ReleaseSafe` 优化
4. `strip` 减小二进制体积

### 运行阶段 (Runtime)

```dockerfile
FROM alpine:3.19

# 最小运行时依赖
RUN apk add --no-cache \
    ca-certificates \
    tzdata

# 安全: 非 root 用户
RUN addgroup -g 1000 zigquant && \
    adduser -u 1000 -G zigquant -s /sbin/nologin -D zigquant

# 复制二进制
COPY --from=builder --chown=zigquant:zigquant \
    /app/zig-out/bin/zigquant /usr/local/bin/

# 创建目录结构
RUN mkdir -p /etc/zigquant /var/lib/zigquant /var/log/zigquant && \
    chown -R zigquant:zigquant /var/lib/zigquant /var/log/zigquant

# 复制默认配置
COPY --chown=zigquant:zigquant \
    config.example.json /etc/zigquant/config.json

USER zigquant
WORKDIR /var/lib/zigquant

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q --spider http://localhost:8080/health || exit 1

ENTRYPOINT ["zigquant"]
CMD ["serve", "--config", "/etc/zigquant/config.json"]
```

---

## 镜像层分析

```
LAYER                SIZE    DESCRIPTION
─────────────────────────────────────────────
alpine:3.19          7.38MB  Base image
ca-certificates      1.12MB  TLS certificates
tzdata               0.82MB  Timezone data
adduser/addgroup     0.01MB  User creation
zigquant binary      ~40MB   Application
config               0.01MB  Configuration
─────────────────────────────────────────────
TOTAL               ~50MB
```

### 体积优化

```bash
# 查看镜像层
docker history zigquant:latest

# 分析镜像
docker run --rm -it wagoodman/dive zigquant:latest
```

---

## 健康检查

### 内置健康检查

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q --spider http://localhost:8080/health || exit 1
```

| 参数 | 值 | 说明 |
|------|-----|------|
| `interval` | 30s | 检查间隔 |
| `timeout` | 3s | 超时时间 |
| `start-period` | 5s | 启动宽限期 |
| `retries` | 3 | 失败重试次数 |

### 健康检查端点

```
GET /health
Response: {"status": "healthy", "version": "1.0.0"}

GET /ready
Response: {"status": "ready", "checks": {...}}
```

### 自定义健康检查脚本

```bash
#!/bin/sh
# deploy/scripts/healthcheck.sh

set -e

# 检查 API 可用性
response=$(wget -q -O - http://localhost:8080/health 2>/dev/null)

# 解析状态
status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

if [ "$status" = "healthy" ]; then
    exit 0
else
    exit 1
fi
```

---

## 入口点脚本

```bash
#!/bin/sh
# deploy/scripts/entrypoint.sh

set -e

# 处理信号
trap 'echo "Shutting down..."; kill -TERM $PID; wait $PID' SIGTERM SIGINT

# 环境变量映射到配置
if [ -n "$ZIGQUANT_API_PORT" ]; then
    export CONFIG_API_PORT=$ZIGQUANT_API_PORT
fi

if [ -n "$ZIGQUANT_LOG_LEVEL" ]; then
    export CONFIG_LOG_LEVEL=$ZIGQUANT_LOG_LEVEL
fi

# 打印启动信息
echo "Starting zigQuant..."
echo "  Config: ${CONFIG_PATH:-/etc/zigquant/config.json}"
echo "  Port: ${ZIGQUANT_API_PORT:-8080}"
echo "  Log Level: ${ZIGQUANT_LOG_LEVEL:-info}"

# 启动应用
exec zigquant "$@" &
PID=$!

# 等待进程
wait $PID
```

---

## Prometheus 配置

```yaml
# deploy/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: []

rule_files: []

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'zigquant'
    static_configs:
      - targets: ['zigquant:8080']
    metrics_path: '/metrics'
    scrape_interval: 10s
    scrape_timeout: 5s
```

---

## Grafana 配置

### 数据源配置

```yaml
# deploy/grafana/provisioning/datasources/prometheus.yml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
```

### 仪表板配置

```yaml
# deploy/grafana/provisioning/dashboards/dashboard.yml
apiVersion: 1

providers:
  - name: 'zigQuant'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: /etc/grafana/provisioning/dashboards
```

### 仪表板 JSON

```json
{
  "dashboard": {
    "title": "zigQuant Trading Dashboard",
    "uid": "zigquant-main",
    "panels": [
      {
        "title": "Total Trades",
        "type": "stat",
        "targets": [
          {
            "expr": "sum(zigquant_trades_total)",
            "legendFormat": "Trades"
          }
        ]
      },
      {
        "title": "Win Rate",
        "type": "gauge",
        "targets": [
          {
            "expr": "avg(zigquant_win_rate)",
            "legendFormat": "Win Rate"
          }
        ]
      },
      {
        "title": "API Latency",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.99, rate(zigquant_api_latency_seconds_bucket[5m]))",
            "legendFormat": "p99"
          },
          {
            "expr": "histogram_quantile(0.95, rate(zigquant_api_latency_seconds_bucket[5m]))",
            "legendFormat": "p95"
          }
        ]
      }
    ]
  }
}
```

---

## 网络配置

### Bridge 网络

```yaml
networks:
  zigquant-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16
```

### 服务发现

服务间通过容器名称通信:
- zigQuant 访问: `http://zigquant:8080`
- Prometheus 访问: `http://prometheus:9090`
- Grafana 访问: `http://grafana:3000`

---

## 卷管理

### 命名卷

```yaml
volumes:
  zigquant-data:
    driver: local
  prometheus-data:
    driver: local
  grafana-data:
    driver: local
```

### 数据持久化

| 卷 | 容器路径 | 用途 |
|-----|----------|------|
| `zigquant-data` | `/var/lib/zigquant` | 策略数据、缓存 |
| `prometheus-data` | `/prometheus` | 指标时序数据 |
| `grafana-data` | `/var/lib/grafana` | 仪表板、用户设置 |

### 备份策略

```bash
# 备份数据卷
docker run --rm \
  -v zigquant-data:/data \
  -v $(pwd)/backup:/backup \
  alpine tar czf /backup/zigquant-backup.tar.gz /data

# 恢复数据卷
docker run --rm \
  -v zigquant-data:/data \
  -v $(pwd)/backup:/backup \
  alpine tar xzf /backup/zigquant-backup.tar.gz -C /
```

---

## 资源限制

### 开发环境

```yaml
services:
  zigquant:
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 256M
```

### 生产环境

```yaml
services:
  zigquant:
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 1G
        reservations:
          cpus: '1'
          memory: 256M
```

---

## 日志管理

### JSON 日志驱动

```yaml
services:
  zigquant:
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"
        compress: "true"
```

### 日志输出到文件

```yaml
services:
  zigquant:
    volumes:
      - ./logs:/var/log/zigquant
    command: ["serve", "--log-file", "/var/log/zigquant/app.log"]
```

### 集中式日志 (Loki)

```yaml
services:
  zigquant:
    logging:
      driver: loki
      options:
        loki-url: "http://loki:3100/loki/api/v1/push"
        loki-batch-size: "400"
```

---

## 安全加固

### 只读文件系统

```yaml
services:
  zigquant:
    read_only: true
    tmpfs:
      - /tmp
      - /var/lib/zigquant/cache
```

### 安全选项

```yaml
services:
  zigquant:
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
```

### Secrets 管理

```yaml
services:
  zigquant:
    secrets:
      - api_key
      - jwt_secret

secrets:
  api_key:
    file: ./secrets/api_key.txt
  jwt_secret:
    file: ./secrets/jwt_secret.txt
```

---

## 开发环境配置

```yaml
# docker-compose.dev.yml
version: '3.8'

services:
  zigquant:
    build:
      context: .
      target: builder  # 使用构建阶段
    volumes:
      - .:/app
      - /app/zig-cache
    command: ["zig", "build", "run", "--", "serve"]
    environment:
      - ZIGQUANT_LOG_LEVEL=debug
```

使用:
```bash
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up
```

---

## CI/CD 集成

### GitHub Actions

```yaml
# .github/workflows/docker.yml
name: Docker Build

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to DockerHub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            davirain/zigquant:${{ github.ref_name }}
            davirain/zigquant:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

*Last updated: 2025-12-28*
