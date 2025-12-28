# Docker 部署 - 容器化部署

> 生产环境容器化部署方案

**状态**: 📋 待开始
**版本**: v1.0.0
**Story**: [Story 050: Docker 部署](../../stories/v1.0.0/STORY_050_DOCKER.md)
**最后更新**: 2025-12-28

---

## 概述

zigQuant Docker 部署提供完整的容器化解决方案，包括多阶段构建、docker-compose 编排、监控栈集成。

### 为什么使用 Docker？

- **一致性**: 开发、测试、生产环境一致
- **可移植**: 跨平台部署无依赖问题
- **可扩展**: 容器编排支持水平扩展
- **隔离性**: 资源隔离，安全可控

### 核心特性

- **多阶段构建**: 最小化镜像体积 (< 50MB)
- **健康检查**: 内置容器健康监控
- **配置外部化**: 环境变量和挂载配置
- **监控栈**: Prometheus + Grafana 开箱即用
- **日志管理**: 结构化日志输出

---

## 快速开始

### 使用 Docker 运行

```bash
# 构建镜像
docker build -t zigquant:latest .

# 运行容器
docker run -d \
  --name zigquant \
  -p 8080:8080 \
  -v $(pwd)/config.json:/etc/zigquant/config.json:ro \
  -e ZIGQUANT_LOG_LEVEL=info \
  zigquant:latest

# 检查状态
curl http://localhost:8080/health
```

### 使用 docker-compose

```bash
# 启动完整栈 (zigQuant + Prometheus + Grafana)
docker-compose up -d

# 查看日志
docker-compose logs -f zigquant

# 停止服务
docker-compose down
```

### 访问服务

| 服务 | URL | 描述 |
|------|-----|------|
| zigQuant API | http://localhost:8080 | REST API |
| Prometheus | http://localhost:9090 | 指标存储 |
| Grafana | http://localhost:3000 | 可视化仪表板 |

---

## 相关文档

- [实现细节](./implementation.md) - Dockerfile 和构建细节
- [配置说明](./configuration.md) - 配置选项和环境变量
- [测试文档](./testing.md) - 容器测试和验证
- [Bug 追踪](./bugs.md) - 已知问题和修复
- [变更日志](./changelog.md) - 版本历史

---

## 镜像规格

### 基础镜像

| 层级 | 镜像 | 用途 |
|------|------|------|
| 构建 | `alpine:3.19` | 编译 Zig 代码 |
| 运行 | `alpine:3.19` | 最小运行时 |

### 镜像体积

```
zigquant:latest    < 50MB
├── alpine base    ~7MB
├── ca-certificates ~1MB
├── zigquant binary ~40MB
└── config files   ~1MB
```

---

## 目录结构

```
deploy/
├── Dockerfile              # 多阶段构建
├── docker-compose.yml      # 完整编排
├── docker-compose.dev.yml  # 开发环境
├── prometheus/
│   └── prometheus.yml      # Prometheus 配置
├── grafana/
│   ├── provisioning/
│   │   ├── dashboards/
│   │   │   └── zigquant.json
│   │   └── datasources/
│   │       └── prometheus.yml
│   └── dashboards/
│       └── trading.json
└── scripts/
    ├── healthcheck.sh      # 健康检查脚本
    └── entrypoint.sh       # 容器入口点
```

---

## Dockerfile

```dockerfile
# ============================================
# Stage 1: Build
# ============================================
FROM alpine:3.19 AS builder

# 安装 Zig
RUN apk add --no-cache \
    zig \
    git \
    ca-certificates

WORKDIR /app

# 复制源码
COPY . .

# 构建 release 版本
RUN zig build -Doptimize=ReleaseSafe

# ============================================
# Stage 2: Runtime
# ============================================
FROM alpine:3.19

# 安装运行时依赖
RUN apk add --no-cache \
    ca-certificates \
    tzdata

# 创建非 root 用户
RUN addgroup -g 1000 zigquant && \
    adduser -u 1000 -G zigquant -s /bin/sh -D zigquant

# 复制构建产物
COPY --from=builder /app/zig-out/bin/zigquant /usr/local/bin/
COPY --from=builder /app/config.example.json /etc/zigquant/config.json

# 创建数据目录
RUN mkdir -p /var/lib/zigquant && \
    chown -R zigquant:zigquant /var/lib/zigquant

# 切换用户
USER zigquant

# 暴露端口
EXPOSE 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q --spider http://localhost:8080/health || exit 1

# 入口点
ENTRYPOINT ["zigquant"]
CMD ["serve", "--config", "/etc/zigquant/config.json"]
```

---

## docker-compose.yml

```yaml
version: '3.8'

services:
  zigquant:
    build:
      context: .
      dockerfile: deploy/Dockerfile
    image: zigquant:latest
    container_name: zigquant
    ports:
      - "8080:8080"
    volumes:
      - ./config.json:/etc/zigquant/config.json:ro
      - zigquant-data:/var/lib/zigquant
    environment:
      - ZIGQUANT_LOG_LEVEL=info
      - ZIGQUANT_API_HOST=0.0.0.0
      - ZIGQUANT_API_PORT=8080
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 3s
      retries: 3
    networks:
      - zigquant-network

  prometheus:
    image: prom/prometheus:v2.48.0
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./deploy/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'
    restart: unless-stopped
    networks:
      - zigquant-network

  grafana:
    image: grafana/grafana:10.2.0
    container_name: grafana
    ports:
      - "3000:3000"
    volumes:
      - ./deploy/grafana/provisioning:/etc/grafana/provisioning:ro
      - grafana-data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    restart: unless-stopped
    depends_on:
      - prometheus
    networks:
      - zigquant-network

volumes:
  zigquant-data:
  prometheus-data:
  grafana-data:

networks:
  zigquant-network:
    driver: bridge
```

---

## 环境变量

| 变量 | 默认值 | 描述 |
|------|--------|------|
| `ZIGQUANT_LOG_LEVEL` | `info` | 日志级别 (debug, info, warn, error) |
| `ZIGQUANT_API_HOST` | `0.0.0.0` | API 监听地址 |
| `ZIGQUANT_API_PORT` | `8080` | API 监听端口 |
| `ZIGQUANT_CONFIG_PATH` | `/etc/zigquant/config.json` | 配置文件路径 |
| `ZIGQUANT_DATA_DIR` | `/var/lib/zigquant` | 数据存储目录 |
| `TZ` | `UTC` | 时区 |

---

## 常用命令

### 构建

```bash
# 构建镜像
docker build -t zigquant:latest .

# 构建并标记版本
docker build -t zigquant:v1.0.0 -t zigquant:latest .

# 无缓存构建
docker build --no-cache -t zigquant:latest .
```

### 运行

```bash
# 前台运行
docker run --rm -p 8080:8080 zigquant:latest

# 后台运行
docker run -d --name zigquant -p 8080:8080 zigquant:latest

# 带配置文件
docker run -d \
  --name zigquant \
  -p 8080:8080 \
  -v $(pwd)/config.json:/etc/zigquant/config.json:ro \
  zigquant:latest

# 交互式调试
docker run --rm -it zigquant:latest /bin/sh
```

### 管理

```bash
# 查看日志
docker logs -f zigquant

# 进入容器
docker exec -it zigquant /bin/sh

# 停止容器
docker stop zigquant

# 删除容器
docker rm zigquant

# 清理未使用镜像
docker image prune
```

### docker-compose

```bash
# 启动所有服务
docker-compose up -d

# 仅启动 zigQuant
docker-compose up -d zigquant

# 重建并启动
docker-compose up -d --build

# 查看状态
docker-compose ps

# 查看日志
docker-compose logs -f

# 停止并删除
docker-compose down

# 停止并删除数据卷
docker-compose down -v
```

---

## 生产部署建议

### 安全

- 使用非 root 用户运行
- 挂载只读配置文件 (`:ro`)
- 不暴露不必要的端口
- 使用 secrets 管理敏感信息

### 资源限制

```yaml
services:
  zigquant:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 128M
```

### 日志配置

```yaml
services:
  zigquant:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

---

## 性能指标

| 指标 | 目标值 |
|------|--------|
| 镜像体积 | < 50MB |
| 启动时间 | < 5s |
| 内存占用 | < 100MB |
| 健康检查响应 | < 100ms |

---

## 未来改进

- [ ] Kubernetes 部署 (Helm Chart)
- [ ] Multi-arch 镜像 (amd64, arm64)
- [ ] GitHub Actions 自动构建
- [ ] Harbor 镜像仓库集成
- [ ] Traefik 反向代理

---

*Last updated: 2025-12-28*
