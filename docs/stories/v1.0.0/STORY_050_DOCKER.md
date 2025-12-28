# Story 050: Docker 部署

**Story ID**: STORY-050
**版本**: v1.0.0
**优先级**: P2
**状态**: 📋 待开始
**依赖**: Story 047-049

---

## 概述

实现 Docker 容器化部署，提供生产级别的容器编排方案，包括 zigQuant 服务、Prometheus 监控和 Grafana 可视化。

### 目标

1. 多阶段构建优化镜像体积
2. docker-compose 一键部署
3. 健康检查端点集成
4. 配置文件挂载支持
5. 日志持久化

---

## Dockerfile

### 多阶段构建

```dockerfile
# ============================================
# Stage 1: Builder
# ============================================
FROM alpine:3.19 AS builder

# 安装 Zig
RUN apk add --no-cache \
    curl \
    xz \
    ca-certificates

# 下载并安装 Zig 0.15.x
ARG ZIG_VERSION=0.15.0
RUN curl -L https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz \
    | tar -xJ -C /usr/local \
    && ln -s /usr/local/zig-linux-x86_64-${ZIG_VERSION}/zig /usr/local/bin/zig

# 复制源码
WORKDIR /app
COPY . .

# 构建 Release 版本
RUN zig build -Doptimize=ReleaseSafe

# ============================================
# Stage 2: Runtime
# ============================================
FROM alpine:3.19 AS runtime

# 安装运行时依赖
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    && rm -rf /var/cache/apk/*

# 创建非 root 用户
RUN addgroup -g 1000 zigquant \
    && adduser -u 1000 -G zigquant -s /bin/sh -D zigquant

# 复制构建产物
COPY --from=builder /app/zig-out/bin/zigquant /usr/local/bin/zigquant
COPY --from=builder /app/src/api/static /app/static

# 创建数据目录
RUN mkdir -p /var/lib/zigquant /var/log/zigquant \
    && chown -R zigquant:zigquant /var/lib/zigquant /var/log/zigquant /app

# 配置文件
COPY deploy/config.example.json /etc/zigquant/config.json

# 切换用户
USER zigquant

# 工作目录
WORKDIR /app

# 暴露端口
EXPOSE 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q --spider http://localhost:8080/health || exit 1

# 环境变量
ENV ZIGQUANT_CONFIG=/etc/zigquant/config.json
ENV ZIGQUANT_LOG_LEVEL=info
ENV TZ=UTC

# 启动命令
ENTRYPOINT ["zigquant"]
CMD ["serve", "--config", "/etc/zigquant/config.json"]
```

### 开发版 Dockerfile

```dockerfile
# Dockerfile.dev
FROM alpine:3.19

# 安装开发依赖
RUN apk add --no-cache \
    curl \
    xz \
    ca-certificates \
    git \
    bash

# 安装 Zig
ARG ZIG_VERSION=0.15.0
RUN curl -L https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz \
    | tar -xJ -C /usr/local \
    && ln -s /usr/local/zig-linux-x86_64-${ZIG_VERSION}/zig /usr/local/bin/zig

WORKDIR /app

# 默认命令
CMD ["zig", "build", "run"]
```

---

## docker-compose.yml

### 生产环境

```yaml
# docker-compose.yml
version: '3.8'

services:
  # ============================================
  # zigQuant 主服务
  # ============================================
  zigquant:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: zigquant
    ports:
      - "8080:8080"
    volumes:
      - ./config.json:/etc/zigquant/config.json:ro
      - zigquant-data:/var/lib/zigquant
      - zigquant-logs:/var/log/zigquant
    environment:
      - ZIGQUANT_LOG_LEVEL=${LOG_LEVEL:-info}
      - ZIGQUANT_API_KEY=${API_KEY}
      - ZIGQUANT_JWT_SECRET=${JWT_SECRET}
      - TZ=${TZ:-UTC}
    restart: unless-stopped
    networks:
      - zigquant-network
    depends_on:
      - prometheus
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 3s
      retries: 3

  # ============================================
  # Prometheus 监控
  # ============================================
  prometheus:
    image: prom/prometheus:v2.48.0
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./deploy/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./deploy/prometheus/alerts:/etc/prometheus/alerts:ro
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'
      - '--web.enable-lifecycle'
    restart: unless-stopped
    networks:
      - zigquant-network

  # ============================================
  # Grafana 可视化
  # ============================================
  grafana:
    image: grafana/grafana:10.2.0
    container_name: grafana
    ports:
      - "3000:3000"
    volumes:
      - ./deploy/grafana/provisioning:/etc/grafana/provisioning:ro
      - ./deploy/grafana/dashboards:/var/lib/grafana/dashboards:ro
      - grafana-data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-admin}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SERVER_ROOT_URL=${GRAFANA_ROOT_URL:-http://localhost:3000}
    restart: unless-stopped
    networks:
      - zigquant-network
    depends_on:
      - prometheus

  # ============================================
  # Alertmanager (可选)
  # ============================================
  alertmanager:
    image: prom/alertmanager:v0.26.0
    container_name: alertmanager
    ports:
      - "9093:9093"
    volumes:
      - ./deploy/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
      - alertmanager-data:/alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
    restart: unless-stopped
    networks:
      - zigquant-network
    profiles:
      - full

# ============================================
# 网络
# ============================================
networks:
  zigquant-network:
    driver: bridge

# ============================================
# 数据卷
# ============================================
volumes:
  zigquant-data:
    driver: local
  zigquant-logs:
    driver: local
  prometheus-data:
    driver: local
  grafana-data:
    driver: local
  alertmanager-data:
    driver: local
```

### 开发环境

```yaml
# docker-compose.dev.yml
version: '3.8'

services:
  zigquant-dev:
    build:
      context: .
      dockerfile: Dockerfile.dev
    container_name: zigquant-dev
    ports:
      - "8080:8080"
    volumes:
      - .:/app
      - zig-cache:/app/zig-cache
    environment:
      - ZIGQUANT_LOG_LEVEL=debug
    command: ["zig", "build", "run", "--", "serve"]
    networks:
      - zigquant-network

  prometheus:
    image: prom/prometheus:v2.48.0
    container_name: prometheus-dev
    ports:
      - "9090:9090"
    volumes:
      - ./deploy/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    networks:
      - zigquant-network

networks:
  zigquant-network:
    driver: bridge

volumes:
  zig-cache:
    driver: local
```

---

## 配置文件模板

### config.example.json

```json
{
  "api": {
    "host": "0.0.0.0",
    "port": 8080,
    "workers": 4,
    "jwt_secret": "CHANGE_ME_IN_PRODUCTION",
    "jwt_expiry_hours": 24,
    "cors_origins": ["*"]
  },
  "exchange": {
    "name": "hyperliquid",
    "api_key": "",
    "api_secret": "",
    "testnet": true
  },
  "trading": {
    "max_position_size": 1.0,
    "max_daily_loss": 0.05,
    "default_leverage": 1
  },
  "notifications": {
    "telegram": {
      "enabled": false,
      "bot_token": "",
      "chat_id": ""
    },
    "email": {
      "enabled": false,
      "provider": "sendgrid",
      "api_key": "",
      "from": "alerts@example.com",
      "to": ["admin@example.com"]
    }
  },
  "logging": {
    "level": "info",
    "format": "json"
  }
}
```

### .env.example

```bash
# zigQuant Configuration
API_KEY=your-exchange-api-key
JWT_SECRET=your-jwt-secret-key-change-in-production
LOG_LEVEL=info
TZ=UTC

# Grafana
GRAFANA_USER=admin
GRAFANA_PASSWORD=admin
GRAFANA_ROOT_URL=http://localhost:3000

# Telegram Notifications
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=

# Email Notifications
SENDGRID_API_KEY=
```

---

## Prometheus 配置

### deploy/prometheus/prometheus.yml

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'zigquant'

scrape_configs:
  - job_name: 'zigquant'
    static_configs:
      - targets: ['zigquant:8080']
    metrics_path: '/metrics'
    scrape_interval: 10s
    scrape_timeout: 5s

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - '/etc/prometheus/alerts/*.yml'
```

---

## Grafana 配置

### deploy/grafana/provisioning/datasources/prometheus.yml

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
```

### deploy/grafana/provisioning/dashboards/default.yml

```yaml
apiVersion: 1

providers:
  - name: 'zigQuant'
    orgId: 1
    folder: 'zigQuant'
    folderUid: 'zigquant'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: /var/lib/grafana/dashboards
```

---

## Makefile

```makefile
# Makefile

.PHONY: build run dev test docker-build docker-run docker-stop clean

# 本地构建
build:
	zig build -Doptimize=ReleaseSafe

# 本地运行
run:
	zig build run -- serve

# 开发模式
dev:
	zig build run -- serve --log-level debug

# 运行测试
test:
	zig build test

# Docker 构建
docker-build:
	docker build -t zigquant:latest .

# Docker 运行 (生产)
docker-run:
	docker-compose up -d

# Docker 运行 (开发)
docker-dev:
	docker-compose -f docker-compose.dev.yml up

# Docker 停止
docker-stop:
	docker-compose down

# Docker 清理
docker-clean:
	docker-compose down -v --rmi local

# 查看日志
logs:
	docker-compose logs -f zigquant

# 清理
clean:
	rm -rf zig-out zig-cache
```

---

## 部署流程

### 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/DaviRain-Su/zigQuant.git
cd zigQuant

# 2. 复制配置文件
cp .env.example .env
cp deploy/config.example.json config.json

# 3. 编辑配置
vim .env
vim config.json

# 4. 启动服务
docker-compose up -d

# 5. 查看日志
docker-compose logs -f zigquant

# 6. 访问服务
# - zigQuant API: http://localhost:8080
# - Prometheus: http://localhost:9090
# - Grafana: http://localhost:3000
```

### 生产部署检查清单

- [ ] 修改 JWT_SECRET
- [ ] 配置交易所 API 密钥
- [ ] 设置正确的 CORS origins
- [ ] 配置通知渠道 (Telegram/Email)
- [ ] 设置 Grafana 管理员密码
- [ ] 配置 TLS/HTTPS (反向代理)
- [ ] 设置日志轮转
- [ ] 配置备份策略

---

## 验收标准

### 功能要求

- [ ] Dockerfile 构建成功
- [ ] docker-compose 启动成功
- [ ] 健康检查通过
- [ ] 配置文件挂载正常
- [ ] 日志持久化正常
- [ ] Prometheus 抓取正常
- [ ] Grafana 仪表板可用

### 性能要求

- [ ] 镜像体积 < 100MB
- [ ] 启动时间 < 10s
- [ ] 内存占用 < 100MB

### 安全要求

- [ ] 非 root 用户运行
- [ ] 敏感配置通过环境变量
- [ ] 无硬编码密钥

---

## 相关文档

- [v1.0.0 Overview](./OVERVIEW.md)
- [Story 051: Operations](./STORY_051_OPERATIONS.md)

---

*最后更新: 2025-12-28*
